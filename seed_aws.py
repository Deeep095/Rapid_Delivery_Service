"""
Seed AWS RDS Database for Rapid Delivery Service
Run this after Terraform deployment completes
"""

import psycopg2
import requests
import json
import sys
import os
import subprocess

print("=" * 60)
print("🌐 AWS RDS Database Seeder")
print("=" * 60)

# Try to read from terraform output first
try:
    print("\n📊 Reading Terraform outputs...")
    os.chdir("terraform-files")
    result = subprocess.run(
        ["terraform", "output", "-json"],
        capture_output=True,
        text=True,
        timeout=30
    )
    os.chdir("..")
    
    if result.returncode == 0:
        outputs = json.loads(result.stdout)
        rds_endpoint = outputs.get("rds_endpoint", {}).get("value", "")
        opensearch_endpoint = outputs.get("opensearch_endpoint", {}).get("value", "")
        
        print(f"✅ Found RDS endpoint: {rds_endpoint}")
        print(f"✅ Found OpenSearch endpoint: {opensearch_endpoint}")
    else:
        print("⚠️  Could not read terraform output, will prompt for values")
        rds_endpoint = ""
        opensearch_endpoint = ""
except Exception as e:
    print(f"⚠️  Error reading terraform output: {e}")
    rds_endpoint = ""
    opensearch_endpoint = ""

# Prompt if not found
if not rds_endpoint:
    rds_endpoint = input("\n📍 Enter RDS Endpoint (from terraform output): ").strip()

if not opensearch_endpoint:
    opensearch_endpoint = input("\n📍 Enter OpenSearch Endpoint (from terraform output): ").strip()

# Ensure https:// prefix for OpenSearch
if opensearch_endpoint and not opensearch_endpoint.startswith("http"):
    opensearch_endpoint = f"https://{opensearch_endpoint}"

print("\n⚠️  Note: ElastiCache Redis is VPC-only and cannot be accessed from your laptop")
print("   Redis data will be populated by EC2 services automatically")

if not rds_endpoint:
    print("❌ RDS endpoint is required!")
    sys.exit(1)

# Parse host and port
if ":" in rds_endpoint:
    DB_HOST, DB_PORT = rds_endpoint.rsplit(":", 1)
    DB_PORT = int(DB_PORT)
else:
    DB_HOST = rds_endpoint
    DB_PORT = 5432

# AWS RDS Configuration
DB_NAME = "postgres"
DB_USER = "postgres"
DB_PASSWORD = "password123"  # From Terraform

# Redis - ElastiCache (VPC-only, can't access from laptop)
if not opensearch_endpoint.startswith("http"):
    opensearch_endpoint = f"https://{opensearch_endpoint}"

print("\n" + "=" * 60)
print("📦 Connecting to AWS Services...")
print("=" * 60)

# Test PostgreSQL connection
print(f"\n⏳ Connecting to RDS PostgreSQL at {DB_HOST}:{DB_PORT}...")
try:
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=10
    )
    print("✅ PostgreSQL connection successful!")
except Exception as e:
    print(f"❌ PostgreSQL connection failed: {e}")
    print("\n💡 Make sure:")
    print("   1. RDS security group allows your IP")
    print("   2. RDS is set to 'publicly_accessible = true'")
    sys.exit(1)

# Create tables
print("\n📦 Creating database tables...")
cur = conn.cursor()

try:
    # Drop and recreate tables
    cur.execute("DROP TABLE IF EXISTS orders CASCADE;")
    cur.execute("DROP TABLE IF EXISTS inventory CASCADE;")
    
    cur.execute("""
        CREATE TABLE inventory (
            warehouse_id VARCHAR(50), 
            item_id VARCHAR(50), 
            stock INT,
            PRIMARY KEY (warehouse_id, item_id)
        );
    """)
    
    cur.execute("""
        CREATE TABLE orders (
            order_id VARCHAR(100) PRIMARY KEY,
            customer_id VARCHAR(50),
            status VARCHAR(20),
            items JSONB,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    
    conn.commit()
    print("✅ Tables created successfully!")
except Exception as e:
    print(f"❌ Table creation failed: {e}")
    conn.rollback()
    sys.exit(1)

# Insert inventory data
print("\n📦 Seeding inventory data...")
inventory_data = [
    ("wh_amer", "apple", 100), ("wh_amer", "milk", 50), 
    ("wh_amer", "bread", 50), ("wh_amer", "coke", 50),
    ("wh_amer", "chips", 75), ("wh_amer", "eggs", 60),
    ("wh_amer", "banana", 80), ("wh_amer", "cookie", 40),
    
    ("wh_rajapark", "apple", 50), ("wh_rajapark", "milk", 50),
    ("wh_rajapark", "bread", 20), ("wh_rajapark", "coke", 100),
    ("wh_rajapark", "chips", 30), ("wh_rajapark", "eggs", 40),
    ("wh_rajapark", "banana", 60), ("wh_rajapark", "cookie", 50),
]

for wh, item, qty in inventory_data:
    cur.execute(
        "INSERT INTO inventory (warehouse_id, item_id, stock) VALUES (%s, %s, %s)",
        (wh, item, qty)
    )

conn.commit()
print(f"✅ Seeded {len(inventory_data)} inventory items")

# Seed OpenSearch
print("\n📦 Seeding OpenSearch with warehouse locations...")
try:
    # Delete existing index
    try:
        requests.delete(f"{opensearch_endpoint}/warehouses", timeout=10)
    except:
        pass
    
    # Create index with mapping
    mapping = {
        "mappings": {
            "properties": {
                "id": {"type": "keyword"},
                "location": {"type": "geo_point"}
            }
        }
    }
    
    resp = requests.put(
        f"{opensearch_endpoint}/warehouses",
        json=mapping,
        headers={"Content-Type": "application/json"},
        timeout=10
    )
    
    if resp.status_code not in [200, 201]:
        print(f"⚠️  Index creation returned: {resp.status_code}")
    
    # Add warehouses
    warehouses = [
        {"id": "wh_amer", "location": {"lat": 26.9900, "lon": 75.8600}},
        {"id": "wh_rajapark", "location": {"lat": 26.9000, "lon": 75.8300}},
        {"id": "wh_ajmer", "location": {"lat": 26.4499, "lon": 74.6399}}
    ]
    
    for wh in warehouses:
        resp = requests.post(
            f"{opensearch_endpoint}/warehouses/_doc/{wh['id']}",
            json=wh,
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        print(f"   Added warehouse: {wh['id']} at ({wh['location']['lat']}, {wh['location']['lon']})")
    
    print(f"✅ Seeded {len(warehouses)} warehouses to OpenSearch")
    
except Exception as e:
    print(f"⚠️  OpenSearch seeding failed: {e}")
    print("   Services may still work, but location-based search will be limited")

# Close connection
cur.close()
conn.close()

print("\n" + "=" * 60)
print("✅ AWS DATABASE SEEDING COMPLETE!")
print("=" * 60)
print("\n📋 What was seeded:")
print(f"   • PostgreSQL: {len(inventory_data)} inventory items")
print(f"   • OpenSearch: 3 warehouse locations")
print("   • Redis: Will be populated automatically by EC2 services")

print("\n📋 Next Steps:")
print("   1. Wait for EC2 instances to finish initializing (~5 mins)")
print("   2. SSH into EC2 and check pods: kubectl get pods -A")
print("   3. Test APIs from your laptop")
print("   4. Update Flutter app with API server IP")
print("\n🎉 Your AWS deployment is ready!")

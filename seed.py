import psycopg2
import redis
import requests
import json
import time
import sys

# =====================================================
# CONFIGURATION
# =====================================================
DB_HOST = "localhost"
DB_PORT = 5432
DB_NAME = "postgres"
DB_USER = "postgres"
DB_PASSWORD = "password"

REDIS_HOST = "localhost"
REDIS_PORT = 6379

OPENSEARCH_URL = "http://localhost:9200"

# =====================================================
# CONNECTION HELPERS
# =====================================================

def wait_for_postgres(max_retries=30, delay=2):
    """Wait for PostgreSQL to be ready"""
    print("⏳ Waiting for PostgreSQL...")
    for i in range(max_retries):
        try:
            conn = psycopg2.connect(
                host=DB_HOST, 
                database=DB_NAME, 
                user=DB_USER, 
                password=DB_PASSWORD, 
                port=DB_PORT,
                connect_timeout=5
            )
            conn.close()
            print("✅ PostgreSQL is ready!")
            return True
        except Exception as e:
            print(f"   Attempt {i+1}/{max_retries}: {e}")
            time.sleep(delay)
    print("❌ PostgreSQL connection failed!")
    return False

def wait_for_redis(max_retries=30, delay=2):
    """Wait for Redis to be ready"""
    print("⏳ Waiting for Redis...")
    for i in range(max_retries):
        try:
            r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, socket_timeout=5)
            r.ping()
            print("✅ Redis is ready!")
            return True
        except Exception as e:
            print(f"   Attempt {i+1}/{max_retries}: {e}")
            time.sleep(delay)
    print("❌ Redis connection failed!")
    return False

def wait_for_opensearch(max_retries=30, delay=2):
    """Wait for OpenSearch to be ready"""
    print("⏳ Waiting for OpenSearch...")
    for i in range(max_retries):
        try:
            res = requests.get(OPENSEARCH_URL, timeout=5)
            if res.status_code == 200:
                print("✅ OpenSearch is ready!")
                return True
        except Exception as e:
            print(f"   Attempt {i+1}/{max_retries}: {e}")
        time.sleep(delay)
    print("❌ OpenSearch connection failed!")
    return False

# =====================================================
# SEED FUNCTIONS
# =====================================================

def setup_db():
    conn = psycopg2.connect(
        host=DB_HOST, 
        database=DB_NAME, 
        user=DB_USER, 
        password=DB_PASSWORD, 
        port=DB_PORT
    )
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    
    cur = conn.cursor()
    # Drop and recreate tables to ensure correct schema
    cur.execute("DROP TABLE IF EXISTS orders CASCADE;")
    cur.execute("DROP TABLE IF EXISTS inventory CASCADE;")
    
    # Create Tables with correct schema
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
    
    # Clear Redis
    r.flushall()
    print("Database tables recreated.")

    # 2. INSERT JAIPUR DATA
    # Amer Warehouse (Near LNMIIT)
    data = [
        ("wh_amer", "apple", 100), ("wh_amer", "milk", 0), 
        ("wh_amer", "bread", 50), ("wh_amer", "coke", 50),
        ("wh_amer", "chips", 20),
        
        # Raja Park Warehouse (City Center)
        ("wh_rajapark", "apple", 50), ("wh_rajapark", "milk", 50),
        ("wh_rajapark", "bread", 20), ("wh_rajapark", "coke", 10),
        ("wh_rajapark", "chips", 0),
    ]
    
    for wh, item, qty in data:
        cur.execute("INSERT INTO inventory (warehouse_id, item_id, stock) VALUES (%s, %s, %s)", (wh, item, qty))
        r.set(f"{wh}:{item}", qty) # Sync to Redis
        
    conn.commit()
    cur.close()
    print(f"Seeded {len(data)} inventory items.")

def setup_opensearch():
    # 3. RESET INDEX
    try:
        requests.delete(f"{OPENSEARCH_URL}/warehouses")
    except: pass
    
    mapping = {
        "mappings": {
            "properties": {
                "id": {"type": "keyword"},
                "location": {"type": "geo_point"}
            }
        }
    }
    requests.put(f"{OPENSEARCH_URL}/warehouses", json=mapping, headers={"Content-Type": "application/json"})

    # 4. ADD WAREHOUSES
    warehouses = [
        # Amer (Approx 8km from LNMIIT)
        {"id": "wh_amer", "location": {"lat": 26.9900, "lon": 75.8600}}, 
        # Raja Park (Approx 15km from LNMIIT)
        {"id": "wh_rajapark", "location": {"lat": 26.9000, "lon": 75.8300}},
        # Ajmer (Too far)
        {"id": "wh_ajmer", "location": {"lat": 26.4499, "lon": 74.6399}} 
    ]
    
    for wh in warehouses:
        res = requests.post(f"{OPENSEARCH_URL}/warehouses/_doc/{wh['id']}", json=wh, headers={"Content-Type": "application/json"})
        print(f"   Added warehouse: {wh['id']} at ({wh['location']['lat']}, {wh['location']['lon']})")
        
    # Refresh index to make data searchable immediately
    requests.post(f"{OPENSEARCH_URL}/warehouses/_refresh")
    print("✅ Seeded 3 Warehouses to OpenSearch.")

def list_warehouses():
    """List all warehouses in OpenSearch"""
    print("\n📍 Current Warehouses in OpenSearch:")
    print("-" * 50)
    try:
        res = requests.get(
            f"{OPENSEARCH_URL}/warehouses/_search",
            json={"size": 100},
            headers={"Content-Type": "application/json"}
        )
        hits = res.json().get('hits', {}).get('hits', [])
        if not hits:
            print("   No warehouses found!")
        for hit in hits:
            wh = hit['_source']
            loc = wh.get('location', {})
            print(f"   • {wh['id']}: lat={loc.get('lat')}, lon={loc.get('lon')}")
        print(f"\nTotal: {len(hits)} warehouses")
    except Exception as e:
        print(f"   Error: {e}")

if __name__ == "__main__":
    print("=" * 50)
    print("🚀 Rapid Delivery Service - Database Seeder")
    print("=" * 50)
    
    # Wait for all services to be ready
    if not wait_for_postgres():
        print("\n❌ Cannot proceed without PostgreSQL!")
        sys.exit(1)
    
    if not wait_for_redis():
        print("\n❌ Cannot proceed without Redis!")
        sys.exit(1)
    
    if not wait_for_opensearch():
        print("\n❌ Cannot proceed without OpenSearch!")
        sys.exit(1)
    
    print("\n" + "=" * 50)
    print("📦 Seeding Data...")
    print("=" * 50)
    
    setup_db()
    setup_opensearch()
    
    # Show what was seeded
    list_warehouses()
    
    print("\n" + "=" * 50)
    print("✅ Seeding Complete!")
    print("=" * 50)
"""
=============================================================
LOCAL SEEDER - Rapid Delivery Service
=============================================================
Seeds LOCAL Docker containers (PostgreSQL, Redis, OpenSearch)
for development and testing WITHOUT AWS.

PREREQUISITES:
  docker-compose up -d  (or run individual containers)

USAGE:
  python local/seed_local.py

This creates:
  - PostgreSQL: items, orders tables + sample data
  - Redis: Inventory for 3 warehouses (Jaipur, Delhi, Mumbai)
  - OpenSearch: Warehouse geo-locations for nearest search
=============================================================
"""

import psycopg2
from opensearchpy import OpenSearch
import redis
import time

# =====================================================
# LOCAL CONFIGURATION - Docker Compose defaults
# =====================================================
POSTGRES_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "database": "rapid_delivery",
    "user": "postgres",
    "password": "postgres"
}

REDIS_CONFIG = {
    "host": "localhost",
    "port": 6379
}

OPENSEARCH_CONFIG = {
    "host": "localhost",
    "port": 9200
}

# =====================================================
# TEST DATA
# =====================================================
ITEMS = [
    ("apple", "Fresh Apple", 1.99),
    ("banana", "Organic Banana", 0.99),
    ("milk", "Whole Milk 1L", 3.49),
    ("bread", "Whole Wheat Bread", 2.99),
    ("coke", "Coca-Cola 500ml", 1.99),
    ("chips", "Potato Chips", 2.49),
    ("eggs", "Farm Fresh Eggs (12)", 4.99),
    ("cookie", "Chocolate Cookies", 3.99),
    ("rice", "Basmati Rice 1kg", 5.99),
    ("water", "Mineral Water 1L", 0.99),
]

WAREHOUSES = [
    ("wh_jaipur", 26.9124, 75.7873, "Jaipur"),
    ("wh_delhi", 28.6139, 77.2090, "Delhi"),
    ("wh_mumbai", 19.0760, 72.8777, "Mumbai"),
]

INVENTORY = {
    "wh_jaipur": {"apple": 100, "banana": 80, "milk": 50, "bread": 50, "coke": 100, "chips": 75, "eggs": 60, "cookie": 40, "rice": 200, "water": 150},
    "wh_delhi": {"apple": 120, "banana": 100, "milk": 60, "bread": 45, "coke": 150, "chips": 90, "eggs": 80, "cookie": 55, "rice": 180, "water": 200},
    "wh_mumbai": {"apple": 80, "banana": 120, "milk": 70, "bread": 55, "coke": 130, "chips": 60, "eggs": 70, "cookie": 35, "rice": 150, "water": 180},
}

# =====================================================
# SEEDING FUNCTIONS
# =====================================================

def seed_postgres():
    """Create tables and seed items in PostgreSQL"""
    print("\n📦 PostgreSQL (localhost:5432)")
    print("-" * 50)
    
    try:
        conn = psycopg2.connect(**POSTGRES_CONFIG)
        cur = conn.cursor()
        
        # Create items table
        cur.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id VARCHAR(50) PRIMARY KEY,
                name VARCHAR(200) NOT NULL,
                price DECIMAL(10,2) NOT NULL
            )
        """)
        
        # Create orders table
        cur.execute("""
            CREATE TABLE IF NOT EXISTS orders (
                id SERIAL PRIMARY KEY,
                items JSONB NOT NULL,
                warehouse_id VARCHAR(50) NOT NULL,
                status VARCHAR(50) DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Insert items
        for item_id, name, price in ITEMS:
            cur.execute("""
                INSERT INTO items (id, name, price) 
                VALUES (%s, %s, %s)
                ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, price = EXCLUDED.price
            """, (item_id, name, price))
            print(f"   ✅ Item: {item_id} - ${price}")
        
        conn.commit()
        cur.close()
        conn.close()
        print(f"   ✅ {len(ITEMS)} items seeded")
        
    except Exception as e:
        print(f"   ❌ Error: {e}")
        print("   Make sure PostgreSQL is running: docker-compose up -d postgres")


def seed_redis():
    """Seed inventory in Redis"""
    print("\n📦 Redis (localhost:6379)")
    print("-" * 50)
    
    try:
        r = redis.Redis(**REDIS_CONFIG, decode_responses=True)
        r.ping()
        
        for warehouse_id, items in INVENTORY.items():
            for item_id, quantity in items.items():
                key = f"{warehouse_id}:{item_id}"
                r.set(key, quantity)
            print(f"   ✅ {warehouse_id}: {len(items)} items")
        
        print(f"   ✅ Total: {sum(len(items) for items in INVENTORY.values())} inventory entries")
        
    except Exception as e:
        print(f"   ❌ Error: {e}")
        print("   Make sure Redis is running: docker-compose up -d redis")


def seed_opensearch():
    """Seed warehouse locations in OpenSearch"""
    print("\n📦 OpenSearch (localhost:9200)")
    print("-" * 50)
    
    try:
        client = OpenSearch(
            hosts=[{"host": OPENSEARCH_CONFIG["host"], "port": OPENSEARCH_CONFIG["port"]}],
            use_ssl=False,
            verify_certs=False
        )
        
        # Delete index if exists
        try:
            client.indices.delete(index="warehouses")
        except:
            pass
        
        # Create index with geo_point mapping
        client.indices.create(
            index="warehouses",
            body={
                "mappings": {
                    "properties": {
                        "id": {"type": "keyword"},
                        "city": {"type": "text"},
                        "location": {"type": "geo_point"}
                    }
                }
            }
        )
        
        # Add warehouses
        for wh_id, lat, lon, city in WAREHOUSES:
            client.index(
                index="warehouses",
                id=wh_id,
                body={
                    "id": wh_id,
                    "location": {"lat": lat, "lon": lon},
                    "city": city
                },
                refresh=True
            )
            print(f"   ✅ {wh_id}: ({lat}, {lon}) - {city}")
        
        print(f"   ✅ {len(WAREHOUSES)} warehouses added")
        
    except Exception as e:
        print(f"   ❌ Error: {e}")
        print("   Make sure OpenSearch is running: docker-compose up -d opensearch")


def wait_for_services(max_wait=30):
    """Wait for Docker services to be ready"""
    print("\n⏳ Waiting for Docker services...")
    
    services = [
        ("PostgreSQL", lambda: psycopg2.connect(**POSTGRES_CONFIG)),
        ("Redis", lambda: redis.Redis(**REDIS_CONFIG).ping()),
        ("OpenSearch", lambda: OpenSearch(hosts=[OPENSEARCH_CONFIG]).info()),
    ]
    
    for name, check in services:
        for i in range(max_wait):
            try:
                check()
                print(f"   ✅ {name} ready")
                break
            except:
                if i == max_wait - 1:
                    print(f"   ⚠️  {name} not available (will try anyway)")
                time.sleep(1)


if __name__ == "__main__":
    print("\n" + "=" * 60)
    print("🌱 LOCAL SEEDER - Rapid Delivery Service")
    print("=" * 60)
    print("Target: Docker containers (localhost)")
    
    seed_postgres()
    seed_redis()
    seed_opensearch()
    
    print("\n" + "=" * 60)
    print("✅ Local seeding complete!")
    print("=" * 60)
    
    print("\n📍 Test coordinates for Flutter app:")
    for wh_id, lat, lon, city in WAREHOUSES:
        print(f"   {city}: {lat}, {lon}")
    
    print("\n🚀 Now run your Flutter app with useAwsBackend = false")

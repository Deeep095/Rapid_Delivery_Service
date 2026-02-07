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
    # Jaipur Region
    ("wh_jaipur_central", 26.9124, 75.7873, "Jaipur Central"),
    ("wh_jaipur_malviya", 26.8505, 75.8043, "Jaipur Malviya Nagar"),
    ("wh_lnmiit", 26.9020, 75.8680, "LNMIIT Jaipur"),
    ("wh_jaipur_amer", 26.9855, 75.8513, "Jaipur Amer"),
    # Delhi NCR
    ("wh_delhi_central", 28.6139, 77.2090, "Delhi Central"),
    ("wh_delhi_gurgaon", 28.4595, 77.0266, "Gurgaon"),
    ("wh_delhi_noida", 28.5355, 77.3910, "Noida"),
    # Other metros
    ("wh_mumbai_central", 19.0760, 72.8777, "Mumbai Central"),
    ("wh_bangalore_central", 12.9716, 77.5946, "Bangalore Central"),
    ("wh_chennai_central", 13.0827, 80.2707, "Chennai Central"),
]

# Products to seed (matching Flutter app catalog)
PRODUCTS = ["apple", "banana", "orange", "grapes", "milk", "eggs", "curd", "paneer", 
            "chips", "cookie", "namkeen", "coke", "water", "juice", "bread", "cake", 
            "rice", "oil", "atta", "icecream"]

# Generate inventory for all warehouses
INVENTORY = {}
for wh_id, _, _, _ in WAREHOUSES:
    INVENTORY[wh_id] = {product: 100 for product in PRODUCTS}

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
        
        # Drop and recreate orders table with correct schema (includes warehouse_id for seller filtering)
        cur.execute("DROP TABLE IF EXISTS orders CASCADE")
        cur.execute("""
            CREATE TABLE orders (
                order_id VARCHAR(50) PRIMARY KEY,
                customer_id VARCHAR(100) NOT NULL,
                warehouse_id VARCHAR(100),
                status VARCHAR(50) DEFAULT 'PENDING',
                items JSONB NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_orders_warehouse ON orders(warehouse_id)")
        print("   ✅ Created orders table with warehouse_id column")
        
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

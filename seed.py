import psycopg2
import redis
import requests
import json
import time

# Connect to Local Services
conn = psycopg2.connect(host="localhost", database="postgres", user="postgres", password="password", port=5432)
r = redis.Redis(host="localhost", port=6379, decode_responses=True)
OPENSEARCH_URL = "http://localhost:9200"

def setup_db():
    cur = conn.cursor()
    # Create Tables
    cur.execute("""
        CREATE TABLE IF NOT EXISTS inventory (
            warehouse_id VARCHAR(50), item_id VARCHAR(50), stock INT,
            PRIMARY KEY (warehouse_id, item_id)
        );
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS orders (
            order_id SERIAL PRIMARY KEY, customer_id VARCHAR(50), items JSONB
        );
    """)
    
    # 1. CLEAR OLD DATA (CRITICAL FIX)
    cur.execute("TRUNCATE TABLE inventory")
    cur.execute("TRUNCATE TABLE orders")
    r.flushall() # Wipes Redis clean
    print("Old data cleared.")

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
        requests.post(f"{OPENSEARCH_URL}/warehouses/_doc/{wh['id']}", json=wh, headers={"Content-Type": "application/json"})
        
    print("Seeded 3 Warehouses to OpenSearch.")

if __name__ == "__main__":
    setup_db()
    setup_opensearch()
"""
=============================================================
LOCAL ADD WAREHOUSE - Rapid Delivery Service
=============================================================
Add/list/delete warehouses in LOCAL Docker containers.

USAGE:
  python local/add_warehouse_local.py              - Add 3 test warehouses
  python local/add_warehouse_local.py list         - List all warehouses
  python local/add_warehouse_local.py add <id> <lat> <lon> [city]
=============================================================
"""

import sys
import requests
import redis

# LOCAL Docker configuration
OPENSEARCH_URL = "http://localhost:9200"
REDIS_HOST = "localhost"
REDIS_PORT = 6379

# Test warehouses
LOCAL_WAREHOUSES = [
    {"id": "wh_jaipur", "lat": 26.9124, "lon": 75.7873, "city": "Jaipur"},
    {"id": "wh_delhi", "lat": 28.6139, "lon": 77.2090, "city": "Delhi"},
    {"id": "wh_mumbai", "lat": 19.0760, "lon": 72.8777, "city": "Mumbai"},
]

DEFAULT_INVENTORY = {
    "apple": 100, "banana": 80, "milk": 50, "bread": 50, "coke": 100,
    "chips": 75, "eggs": 60, "cookie": 40, "rice": 200, "water": 150,
}


def add_warehouse(warehouse_id: str, lat: float, lon: float, city: str = ""):
    """Add a warehouse to local OpenSearch and Redis"""
    print(f"\n📦 Adding: {warehouse_id} ({city})")
    print(f"   Location: ({lat}, {lon})")
    
    # OpenSearch
    try:
        res = requests.put(
            f"{OPENSEARCH_URL}/warehouses/_doc/{warehouse_id}",
            json={"id": warehouse_id, "location": {"lat": lat, "lon": lon}, "city": city},
            headers={"Content-Type": "application/json"}
        )
        print(f"   ✅ OpenSearch: {'OK' if res.status_code in [200, 201] else res.status_code}")
    except Exception as e:
        print(f"   ❌ OpenSearch: {e}")
    
    # Redis
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        for item_id, qty in DEFAULT_INVENTORY.items():
            r.set(f"{warehouse_id}:{item_id}", qty)
        print(f"   ✅ Redis: {len(DEFAULT_INVENTORY)} items")
    except Exception as e:
        print(f"   ❌ Redis: {e}")


def add_all():
    """Add all test warehouses"""
    print("\n🏪 Adding Test Warehouses (Local Docker)")
    print("-" * 50)
    
    # Ensure index exists
    try:
        requests.put(f"{OPENSEARCH_URL}/warehouses", json={
            "mappings": {"properties": {"location": {"type": "geo_point"}}}
        })
    except:
        pass
    
    for wh in LOCAL_WAREHOUSES:
        add_warehouse(wh["id"], wh["lat"], wh["lon"], wh.get("city", ""))
    
    print("\n✅ Done! Warehouses ready for local testing.")


def list_warehouses():
    """List all warehouses"""
    print("\n📍 Local Warehouses:")
    try:
        res = requests.get(f"{OPENSEARCH_URL}/warehouses/_search", json={"size": 100})
        for hit in res.json().get('hits', {}).get('hits', []):
            wh = hit['_source']
            loc = wh.get('location', {})
            print(f"   • {wh['id']}: ({loc.get('lat')}, {loc.get('lon')}) - {wh.get('city', '')}")
    except Exception as e:
        print(f"   ❌ Error: {e}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        add_all()
        list_warehouses()
    elif sys.argv[1] == "list":
        list_warehouses()
    elif sys.argv[1] == "add" and len(sys.argv) >= 5:
        add_warehouse(sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), 
                     sys.argv[5] if len(sys.argv) > 5 else "")
    else:
        print(__doc__)

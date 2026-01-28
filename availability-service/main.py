import os
import json
import requests
import redis
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware  
from pydantic import BaseModel
from typing import Optional

# Pydantic models for request bodies
class StockUpdateRequest(BaseModel):
    stock: int

# AWS SigV4 Authentication for OpenSearch
def get_aws_auth():
    """Get AWS SigV4 auth for OpenSearch requests"""
    try:
        import boto3
        from requests_aws4auth import AWS4Auth
        
        region = os.environ.get('AWS_REGION', 'us-east-1')
        credentials = boto3.Session().get_credentials()
        if credentials:
            return AWS4Auth(
                credentials.access_key,
                credentials.secret_key,
                region,
                'es',
                session_token=credentials.token
            )
    except ImportError:
        print("Warning: boto3/requests-aws4auth not available, using unsigned requests")
    except Exception as e:
        print(f"Warning: AWS auth setup failed: {e}")
    return None

AWS_AUTH = get_aws_auth()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins (Flutter Web, Mobile, etc.)
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods (GET, POST, etc.)
    allow_headers=["*"],  # Allows all headers
)

# Environment variables (Defaults provided for local testing)
OPENSEARCH_URL = os.environ.get('OPENSEARCH_URL', 'http://localhost:9200')
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))

# Initialize Redis Connection
# In production, add error handling if Redis is down
try:
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
except Exception as e:
    print(f"Warning: Redis connection failed: {e}")
    r = None

@app.get("/")
def health_check():
    return {"status": "healthy", "service": "availability-service"}

@app.get("/availability")
def check_availability(
    item_id: str = Query(...),
    lat: float = Query(...),
    lon: float = Query(...)
):
    if not r:
        raise HTTPException(status_code=503, detail="Redis unavailable")

    # 1. Search OpenSearch for warehouses sorted by distance
    # here we just take for size 10, but we will filter them manually
    query = {
        "size": 10, 
        "sort": [
            { "_geo_distance": { "location": { "lat": lat, "lon": lon }, "order": "asc", "unit": "km" } }
        ]
    }

    try:
        url = f"{OPENSEARCH_URL}/warehouses/_search"
        res = requests.get(url, json=query, auth=AWS_AUTH, headers={"Content-Type": "application/json"})
        hits = res.json().get('hits', {}).get('hits', [])
    except Exception as e:
        return {"available": False, "reason": "Search failed"}

    # 2. THE INTELLIGENT LOOP
    for hit in hits:
        warehouse_id = hit['_source']['id']
        distance = hit['sort'][0] # Distance in KM
        
        # RULE 1: Max Distance Limit (30km)
        if distance > 30.0:
            # Since hits are sorted, if this one is too far, all subsequent ones are too.
            # We stop immediately.
            break 
            
        # RULE 2: Check Stock
        key = f"{warehouse_id}:{item_id}"
        qty = r.get(key)
        
        if qty is not None and int(qty) > 0:
            # Success! We found the closest VALID warehouse
            return {
                "available": True,
                "warehouse_id": warehouse_id,
                "distance_km": distance,
                "quantity": int(qty)
            }

    # If loop finishes without returning, no valid warehouse was found
    return {"available": False, "message": "No stock or no delivery in your area"}


# =====================================================
# INVENTORY MANAGEMENT ENDPOINTS (for Manager flow)
# =====================================================

@app.get("/warehouses")
def get_warehouses():
    """Get list of all warehouses from OpenSearch"""
    try:
        query = {"size": 100, "query": {"match_all": {}}}
        url = f"{OPENSEARCH_URL}/warehouses/_search"
        res = requests.get(url, json=query, auth=AWS_AUTH, headers={"Content-Type": "application/json"})
        hits = res.json().get('hits', {}).get('hits', [])
        
        warehouses = []
        for hit in hits:
            source = hit['_source']
            warehouses.append({
                "id": source.get('id'),
                "city": source.get('city'),
                "lat": source.get('location', {}).get('lat'),
                "lon": source.get('location', {}).get('lon'),
            })
        
        return {"warehouses": warehouses, "count": len(warehouses)}
    except Exception as e:
        print(f"Error fetching warehouses: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch warehouses: {str(e)}")


@app.get("/inventory/{warehouse_id}")
def get_warehouse_inventory(warehouse_id: str):
    """Get all inventory for a specific warehouse from Redis"""
    if not r:
        raise HTTPException(status_code=503, detail="Redis unavailable")
    
    try:
        # Scan Redis for all keys matching this warehouse
        pattern = f"{warehouse_id}:*"
        keys = list(r.scan_iter(pattern))
        
        inventory = []
        for key in keys:
            item_id = key.split(':')[1] if ':' in key else key
            qty = r.get(key)
            inventory.append({
                "product_id": item_id,
                "name": _get_product_name(item_id),
                "category": _get_product_category(item_id),
                "stock": int(qty) if qty else 0,
                "min_stock": 10,  # Default threshold
                "price": _get_product_price(item_id),
            })
        
        return {"inventory": inventory, "warehouse_id": warehouse_id, "count": len(inventory)}
    except Exception as e:
        print(f"Error fetching inventory: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch inventory: {str(e)}")


@app.put("/inventory/{warehouse_id}/{product_id}")
def update_stock(warehouse_id: str, product_id: str, data: StockUpdateRequest):
    """Update stock for a specific product in a warehouse - persists to Redis"""
    if not r:
        raise HTTPException(status_code=503, detail="Redis unavailable")
    
    try:
        key = f"{warehouse_id}:{product_id}"
        new_stock = data.stock
        
        # Get old stock for logging
        old_stock = r.get(key)
        old_stock = int(old_stock) if old_stock else 0
        
        # Update Redis
        r.set(key, new_stock)
        
        print(f"📦 Stock updated: {key} | {old_stock} → {new_stock}")
        
        return {
            "success": True,
            "warehouse_id": warehouse_id,
            "product_id": product_id,
            "old_stock": old_stock,
            "new_stock": new_stock,
            "message": f"Stock updated from {old_stock} to {new_stock}"
        }
    except Exception as e:
        print(f"Error updating stock: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to update stock: {str(e)}")


# =====================================================
# HELPER FUNCTIONS
# =====================================================

# Product catalog (matches Flutter models.dart)
PRODUCT_CATALOG = {
    "apple": {"name": "Red Apple", "category": "Fruits", "price": 120},
    "milk": {"name": "Fresh Milk", "category": "Dairy", "price": 65},
    "bread": {"name": "Wheat Bread", "category": "Bakery", "price": 45},
    "eggs": {"name": "Farm Eggs (12)", "category": "Dairy", "price": 85},
    "chips": {"name": "Potato Chips", "category": "Snacks", "price": 35},
    "coke": {"name": "Cola Can", "category": "Beverages", "price": 40},
    "banana": {"name": "Bananas", "category": "Fruits", "price": 60},
    "cheese": {"name": "Cheese Slice", "category": "Dairy", "price": 150},
    "juice": {"name": "Orange Juice", "category": "Beverages", "price": 95},
    "butter": {"name": "Butter", "category": "Dairy", "price": 55},
    "rice": {"name": "Basmati Rice", "category": "Grains", "price": 180},
    "pasta": {"name": "Pasta", "category": "Grains", "price": 75},
    "chicken": {"name": "Chicken Breast", "category": "Meat", "price": 320},
    "fish": {"name": "Fresh Fish", "category": "Meat", "price": 280},
    "tomato": {"name": "Tomatoes", "category": "Vegetables", "price": 40},
    "potato": {"name": "Potatoes", "category": "Vegetables", "price": 30},
    "onion": {"name": "Onions", "category": "Vegetables", "price": 35},
    "coffee": {"name": "Coffee Beans", "category": "Beverages", "price": 450},
    "tea": {"name": "Green Tea", "category": "Beverages", "price": 120},
    "chocolate": {"name": "Chocolate Bar", "category": "Snacks", "price": 80},
}

def _get_product_name(product_id: str) -> str:
    return PRODUCT_CATALOG.get(product_id, {}).get('name', product_id.replace('_', ' ').title())

def _get_product_category(product_id: str) -> str:
    return PRODUCT_CATALOG.get(product_id, {}).get('category', 'General')

def _get_product_price(product_id: str) -> int:
    return PRODUCT_CATALOG.get(product_id, {}).get('price', 100)
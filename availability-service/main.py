import os
import json
import requests
import redis
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware  
from typing import Optional

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
        res = requests.get(url, json=query)
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
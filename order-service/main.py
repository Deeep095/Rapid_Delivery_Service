# import os
# import json
# import psycopg2
# from fastapi import FastAPI, HTTPException
# from fastapi.middleware.cors import CORSMiddleware
# from pydantic import BaseModel
# from typing import List

# app = FastAPI()
# app.add_middleware(
#     CORSMiddleware,
#     allow_origins=["*"],
#     allow_credentials=True,
#     allow_methods=["*"],
#     allow_headers=["*"],
# )

# # Environment Variables
# DB_HOST = os.environ.get('DB_HOST', 'postgres')
# DB_NAME = os.environ.get('DB_NAME', 'postgres')
# DB_USER = os.environ.get('DB_USER', 'postgres')
# DB_PASS = os.environ.get('DB_PASS', 'password')
# # For local testing, we print to console instead of sending to real SQS
# SQS_QUEUE_URL = os.environ.get('ORDER_QUEUE_URL', 'mock-queue')

# # Pydantic Models (Input Validation)
# class OrderItem(BaseModel):
#     item_id: str
#     warehouse_id: str
#     quantity: int

# class OrderRequest(BaseModel):
#     customer_id: str
#     items: List[OrderItem]

# def get_db_connection():
#     return psycopg2.connect(
#         host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS
#     )

# @app.post("/order")
# def place_order(order: OrderRequest):
#     conn = get_db_connection()
#     cursor = conn.cursor()
    
#     try:
#         # 1. Start Transaction
#         # In Python psycopg2, transactions are implicit when you start executing commands
        
#         items_data = []
        
#         for item in order.items:
#             # 2. LOCK ROW (ACID) - The "Resume" Logic
#             cursor.execute(
#                 "SELECT stock FROM inventory WHERE item_id=%s AND warehouse_id=%s FOR UPDATE",
#                 (item.item_id, item.warehouse_id)
#             )
#             row = cursor.fetchone()
            
#             if not row:
#                 raise Exception(f"Item {item.item_id} not found in warehouse {item.warehouse_id}")
            
#             stock = row[0]
#             if stock < item.quantity:
#                 raise Exception(f"Insufficient stock for item {item.item_id}")
            
#             # 3. Update Stock
#             new_stock = stock - item.quantity
#             cursor.execute(
#                 "UPDATE inventory SET stock=%s WHERE item_id=%s AND warehouse_id=%s",
#                 (new_stock, item.item_id, item.warehouse_id)
#             )
            
#             # Record item details for the order log
#             items_data.append(item.dict())

#         # 4. Create Order Record
#         items_json = json.dumps(items_data)
#         cursor.execute(
#             "INSERT INTO orders (customer_id, status, items) VALUES (%s, %s, %s) RETURNING order_id",
#             (order.customer_id, 'PENDING', items_json)
#         )
#         order_id = cursor.fetchone()[0]
        
#         # 5. Commit Transaction
#         conn.commit()
        
#         # 6. Mock SQS (Simulate sending message)
#         print(f"SQS MESSAGE SENT: Order {order_id} placed for items {items_data}")
        
#         return {"status": "success", "order_id": order_id}

#     except Exception as e:
#         conn.rollback()
#         raise HTTPException(status_code=400, detail=str(e))
#     finally:
#         cursor.close()
#         conn.close()

#         # NEW: Model for Order Response
# class OrderResponse(BaseModel):
#     order_id: int
#     status: str
#     items: List[dict]
#     created_at: str

# @app.get("/orders/{customer_id}")
# def get_order_history(customer_id: str):
#     conn = get_db_connection()
#     cursor = conn.cursor()
#     try:
#         # Query Aurora/Postgres for user's orders
#         cursor.execute(
#             "SELECT order_id, status, items, created_at FROM orders WHERE customer_id = %s ORDER BY order_id DESC",
#             (customer_id,)
#         )
#         rows = cursor.fetchall()
        
#         history = []
#         for row in rows:
#             # Parse JSON items from DB
#             items_data = row[2] if isinstance(row[2], list) else json.loads(row[2])
            
#             history.append({
#                 "order_id": row[0],
#                 "status": row[1], # e.g., 'PENDING'
#                 "items": items_data,
#                 "created_at": str(row[3])
#             })
            
#         return history
#     except Exception as e:
#         raise HTTPException(status_code=500, detail=str(e))
#     finally:
#         cursor.close()
#         conn.close()



import os
import json
import boto3
import uuid
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Config
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')
REGION = "us-east-1"
sqs = boto3.client('sqs', region_name=REGION)

class OrderItem(BaseModel):
    item_id: str
    warehouse_id: str
    quantity: int

class OrderRequest(BaseModel):
    customer_id: str
    items: List[OrderItem]

@app.post("/order")
def place_order(order: OrderRequest):
    order_id = str(uuid.uuid4()) # Generate ID immediately
    
    message_body = {
        "order_id": order_id,
        "customer_id": order.customer_id,
        "items": [item.dict() for item in order.items]
    }

    try:
        # Send to SQS
        sqs.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(message_body)
        )
        return {"status": "Queued", "order_id": order_id, "message": "Order received and processing"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Note: The GET /orders history endpoint connects to DB, 
# so keeping the DB connection logic ONLY for that GET endpoint.
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
import psycopg2
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional

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
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')  # SNS topic for notifications
REGION = os.environ.get("AWS_REGION", "us-east-1")
ENV = os.getenv("ENV", "prod")

# Database Config
DB_HOST = os.environ.get('DB_HOST', 'postgres')
DB_PORT = int(os.environ.get('DB_PORT', '5432'))
DB_NAME = os.environ.get('DB_NAME', 'postgres')
DB_USER = os.environ.get('DB_USER', 'postgres')
DB_PASS = os.environ.get('DB_PASS', 'password')

if ENV != "local":
    sqs = boto3.client("sqs", region_name=REGION)
    sns = boto3.client("sns", region_name=REGION)
else:
    sqs = None
    sns = None

def get_db_connection():
    """Get PostgreSQL database connection"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            connect_timeout=5
        )
        return conn
    except Exception as e:
        print(f"❌ DB Connection Error: {e}")
        raise HTTPException(status_code=503, detail="Database unavailable")


class OrderItem(BaseModel):
    item_id: str
    warehouse_id: str
    quantity: int

class OrderRequest(BaseModel):
    customer_id: str
    items: List[OrderItem]

@app.get("/")
def health_check():
    return {"status": "healthy", "service": "order-service"}

@app.post("/orders")
def place_order(order: OrderRequest):
    order_id = str(uuid.uuid4())
    
    # Extract primary warehouse_id from the first item (all items should be from same warehouse in a single order)
    primary_warehouse_id = order.items[0].warehouse_id if order.items else None
    
    message_body = {
        "order_id": order_id,
        "customer_id": order.customer_id,
        "warehouse_id": primary_warehouse_id,
        "items": [item.dict() for item in order.items]
    }

    try:
        # 1. Store order in database with warehouse_id for seller filtering
        conn = get_db_connection()
        cursor = conn.cursor()
        
        try:
            cursor.execute("""
                INSERT INTO orders (order_id, customer_id, warehouse_id, status, items, created_at) 
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                order_id,
                order.customer_id,
                primary_warehouse_id,
                'PENDING',
                json.dumps(message_body['items']),
                datetime.utcnow()
            ))
            conn.commit()
            print(f"✅ Order {order_id} saved to database (warehouse: {primary_warehouse_id})")
        except Exception as db_error:
            conn.rollback()
            print(f"⚠️ DB Error (order may not be saved): {db_error}")
            # Continue anyway - order can be processed from SQS
        finally:
            cursor.close()
            conn.close()
        
        # 2. Send to SQS for processing
        if ENV == "local":
            print(f"📦 LOCAL ORDER: {order_id}")
            print(f"   Customer: {order.customer_id}")
            print(f"   Items: {message_body['items']}")
        else:
            sqs.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps(message_body)
            )
            print(f"📤 Order {order_id} sent to SQS")
        
        return {"status": "success", "order_id": order_id, "message": "Order placed successfully"}
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Order Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/orders/{customer_id}")
def get_order_history(customer_id: str):
    """Get order history from database"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT order_id, customer_id, status, items, created_at 
            FROM orders 
            WHERE customer_id = %s 
            ORDER BY created_at DESC
            LIMIT 50
        """, (customer_id,))
        
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        
        orders = []
        for row in rows:
            # Parse items JSON from database
            items_data = row[3] if isinstance(row[3], list) else json.loads(row[3])
            
            orders.append({
                "order_id": row[0],
                "customer_id": row[1],
                "status": row[2],
                "items": items_data,
                "created_at": row[4].isoformat() if row[4] else None
            })
        
        return orders
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Order History Error: {e}")
        # Return empty list instead of error for better UX
        return []


# =====================================================
# SELLER/WAREHOUSE ORDER ENDPOINTS
# =====================================================

@app.get("/warehouse/{warehouse_id}/orders")
def get_warehouse_orders(warehouse_id: str):
    """Get orders for a specific warehouse (for sellers/managers)"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT order_id, customer_id, warehouse_id, status, items, created_at 
            FROM orders 
            WHERE warehouse_id = %s 
            ORDER BY created_at DESC
            LIMIT 100
        """, (warehouse_id,))
        
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        
        orders = []
        for row in rows:
            # Parse items JSON from database
            items_data = row[4] if isinstance(row[4], list) else json.loads(row[4])
            
            orders.append({
                "order_id": row[0],
                "customer_id": row[1],
                "warehouse_id": row[2],
                "status": row[3],
                "items": items_data,
                "created_at": row[5].isoformat() if row[5] else None
            })
        
        return {"orders": orders, "count": len(orders), "warehouse_id": warehouse_id}
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Warehouse Orders Error: {e}")
        return {"orders": [], "count": 0, "warehouse_id": warehouse_id}


# =====================================================
# SNS NOTIFICATION ENDPOINTS
# =====================================================

class SubscribeRequest(BaseModel):
    warehouse_id: str
    email: str
    notification_type: Optional[str] = "all"  # 'orders', 'low_stock', 'all'

@app.post("/subscribe")
def subscribe_to_notifications(request: SubscribeRequest):
    """Subscribe email to SNS notifications for a warehouse"""
    if ENV == "local":
        print(f"📧 LOCAL: Would subscribe {request.email} to {request.warehouse_id} notifications")
        return {
            "success": True,
            "message": f"Subscribed {request.email} to notifications (local mode)",
            "warehouse_id": request.warehouse_id
        }
    
    if not SNS_TOPIC_ARN:
        raise HTTPException(status_code=503, detail="SNS notifications not configured")
    
    try:
        # Subscribe email to SNS topic with filter policy
        response = sns.subscribe(
            TopicArn=SNS_TOPIC_ARN,
            Protocol='email',
            Endpoint=request.email,
            Attributes={
                'FilterPolicy': json.dumps({
                    'warehouse_id': [request.warehouse_id],
                    'notification_type': [request.notification_type, 'all']
                })
            }
        )
        
        subscription_arn = response.get('SubscriptionArn', 'pending confirmation')
        
        return {
            "success": True,
            "message": f"Subscription pending - check {request.email} for confirmation",
            "subscription_arn": subscription_arn,
            "warehouse_id": request.warehouse_id
        }
    except Exception as e:
        print(f"❌ SNS Subscribe Error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to subscribe: {str(e)}")


@app.post("/notify")
def send_notification(data: dict):
    """Send notification via SNS (internal use)"""
    if ENV == "local":
        print(f"📢 LOCAL NOTIFICATION: {data}")
        return {"success": True, "message": "Notification logged (local mode)"}
    
    if not SNS_TOPIC_ARN:
        return {"success": False, "message": "SNS not configured"}
    
    try:
        warehouse_id = data.get('warehouse_id', 'unknown')
        notification_type = data.get('type', 'order')
        message = data.get('message', 'New notification from Rapid Delivery')
        
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=message,
            Subject=f"Rapid Delivery - {notification_type.title()} Alert",
            MessageAttributes={
                'warehouse_id': {
                    'DataType': 'String',
                    'StringValue': warehouse_id
                },
                'notification_type': {
                    'DataType': 'String',
                    'StringValue': notification_type
                }
            }
        )
        
        return {
            "success": True,
            "message_id": response.get('MessageId'),
            "warehouse_id": warehouse_id
        }
    except Exception as e:
        print(f"❌ SNS Publish Error: {e}")
        return {"success": False, "error": str(e)}
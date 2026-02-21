import os
import json
import time
import psycopg2
import redis
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# Environment
ENV = os.environ.get("ENV", "prod")
SQS_QUEUE_URL = os.environ.get("SQS_QUEUE_URL")
DB_HOST = os.environ.get("DB_HOST")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "rapid_delivery")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASS = os.environ.get("DB_PASS", "postgres")
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))

# Local mode doesn't require SQS
if ENV != "local" and not SQS_QUEUE_URL:
    raise RuntimeError("SQS_QUEUE_URL is required in production mode")

if not DB_HOST:
    raise RuntimeError("DB_HOST is required")

logging.info(f"Starting fulfillment worker (ENV={ENV})")
logging.info(f"DB Host: {DB_HOST}:{DB_PORT}/{DB_NAME}")

# Initialize SQS only in production
sqs = None
if ENV != "local":
    import boto3
    AWS_REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    if not AWS_REGION:
        temp_session = boto3.session.Session()
        AWS_REGION = temp_session.region_name
    if not AWS_REGION:
        raise RuntimeError("AWS region could not be resolved.")
    logging.info(f"AWS Region: {AWS_REGION}")
    logging.info(f"SQS Queue: {SQS_QUEUE_URL}")
    sqs = boto3.client("sqs", region_name=AWS_REGION)

# Redis connection for stock updates
try:
    redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    redis_client.ping()
    logging.info(f"Redis connected: {REDIS_HOST}:{REDIS_PORT}")
except Exception as e:
    logging.warning(f"Redis not available: {e}")
    redis_client = None


# Database Connection
def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

# Update Redis stock after order processing
def update_redis_stock(warehouse_id: str, item_id: str, quantity: int):
    if redis_client:
        key = f"{warehouse_id}:{item_id}"
        try:
            current = redis_client.get(key)
            if current:
                new_stock = max(0, int(current) - quantity)
                redis_client.set(key, new_stock)
                logging.info(f"Redis updated: {key} = {new_stock}")
        except Exception as e:
            logging.warning(f"Redis update failed: {e}")

# Order Processing Logic
def process_order(order_data: dict) -> bool:
    order_id = order_data.get("order_id")
    items = order_data.get("items", [])
    warehouse_id = order_data.get("warehouse_id")

    if not order_id or not items:
        logging.error("Invalid order payload")
        return False

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        logging.info(f"Processing order {order_id}")

        # Update order status to PROCESSING
        cur.execute(
            "UPDATE orders SET status = %s WHERE order_id = %s AND status = %s",
            ('PROCESSING', order_id, 'PENDING')
        )
        
        if cur.rowcount == 0:
            logging.info(f"Order {order_id} already processed or not found")
            conn.rollback()
            return True

        # Update Redis stock for each item
        for item in items:
            item_warehouse = item.get("warehouse_id", warehouse_id)
            update_redis_stock(item_warehouse, item["item_id"], item["quantity"])

        # Mark order as COMPLETED
        cur.execute(
            "UPDATE orders SET status = %s WHERE order_id = %s",
            ('COMPLETED', order_id)
        )

        conn.commit()
        logging.info(f"Order {order_id} completed successfully")
        return True

    except Exception as e:
        conn.rollback()
        logging.error(f"Order {order_id} failed: {e}")
        # Mark as FAILED
        try:
            cur.execute(
                "UPDATE orders SET status = %s WHERE order_id = %s",
                ('FAILED', order_id)
            )
            conn.commit()
        except:
            pass
        return False

    finally:
        cur.close()
        conn.close()


# LOCAL MODE: Poll database for pending orders
def poll_database_forever():
    logging.info("LOCAL MODE: Polling database for pending orders...")
    
    while True:
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            # Find pending orders
            cur.execute("""
                SELECT order_id, customer_id, warehouse_id, items 
                FROM orders 
                WHERE status = 'PENDING' 
                ORDER BY created_at ASC 
                LIMIT 5
            """)
            
            orders = cur.fetchall()
            cur.close()
            conn.close()
            
            if not orders:
                time.sleep(2)  # No pending orders, wait
                continue
            
            for order in orders:
                order_data = {
                    "order_id": order[0],
                    "customer_id": order[1],
                    "warehouse_id": order[2],
                    "items": order[3] if isinstance(order[3], list) else json.loads(order[3])
                }
                process_order(order_data)
                
        except Exception as e:
            logging.error(f"Database polling error: {e}")
            time.sleep(5)


# PRODUCTION MODE: Poll SQS for orders
def poll_sqs_forever():
    logging.info("PRODUCTION MODE: Polling SQS for orders...")

    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20
            )

            messages = response.get("Messages", [])

            if not messages:
                time.sleep(2)
                continue

            for msg in messages:
                receipt_handle = msg["ReceiptHandle"]
                body = json.loads(msg["Body"])

                if process_order(body):
                    sqs.delete_message(
                        QueueUrl=SQS_QUEUE_URL,
                        ReceiptHandle=receipt_handle
                    )

        except Exception as e:
            logging.error(f"SQS polling error: {e}")
            time.sleep(5)


# Entrypoint
if __name__ == "__main__":
    if ENV == "local":
        poll_database_forever()
    else:
        poll_sqs_forever()

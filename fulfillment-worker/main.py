import os
import json
import boto3
import time
import psycopg2

# Config
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')
DB_HOST = os.environ.get('DB_HOST')
DB_NAME = "postgres"
DB_USER = "postgres"
DB_PASS = "password123"
REGION = os.environ.get("AWS_REGION")

if not SQS_QUEUE_URL:
    raise RuntimeError("SQS_QUEUE_URL is required")

if not DB_HOST:
    raise RuntimeError("DB_HOST is required")

if not REGION:
    raise RuntimeError("AWS_REGION or AWS_DEFAULT_REGION is required")

print(f"Starting fulfillment worker for queue: {SQS_QUEUE_URL} in region: {REGION}")

sqs = boto3.client('sqs', region_name=REGION)


def connect_db():
    return psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

def process_order(body):
    data = json.loads(body)
    order_id = data.get("order_id")
    items = data.get("items")
    customer_id = data.get("customer_id")

    conn = connect_db()
    cur = conn.cursor()
    
    try:
        print(f"Processing Order {order_id}...")
        cur.execute(
            "SELECT 1 FROM orders WHERE order_id = %s",
            (order_id,)
        )
        if cur.fetchone():
            print(f"Order {order_id} already processed, skipping")
            return True
        
        # 1. Start ACID Transaction
        for item in items:
            cur.execute(
                """
                SELECT stock FROM inventory
                WHERE item_id = %s AND warehouse_id = %s
                FOR UPDATE
                """,
                (item["item_id"], item["warehouse_id"])
            )
            row = cur.fetchone()
            if not row or row[0] < item["quantity"]:
                raise Exception(f"Insufficient stock for {item['item_id']}")

            new_stock = row[0] - item["quantity"]
            cur.execute(
                "UPDATE inventory SET stock = %s WHERE item_id = %s AND warehouse_id = %s",
                (new_stock, item["item_id"], item["warehouse_id"])
            )

        # 2. Insert Order Record
        cur.execute(
            "INSERT INTO orders (order_id, customer_id, items) VALUES (%s, %s, %s)",
            (order_id, customer_id, json.dumps(items))
        )

        conn.commit()
        print(f"Order {order_id} processed successfully")
        return True
    except Exception as e:
        conn.rollback()
        print(f"Order {order_id} failed: {e}")
        return False

    finally:
        cur.close()
        conn.close()

    

def poll_sqs():
    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20
            )

            if "Messages" in response:
                for msg in response["Messages"]:
                    body = msg["Body"]
                    receipt = msg["ReceiptHandle"]

                    if process_order(body):
                        sqs.delete_message(
                            QueueUrl=SQS_QUEUE_URL,
                            ReceiptHandle=receipt
                        )
        except Exception as e:
            print(f"SQS polling error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    poll_sqs()
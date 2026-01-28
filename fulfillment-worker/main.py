import os
import json
import boto3
import time
import psycopg2
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

SQS_QUEUE_URL = os.environ.get("SQS_QUEUE_URL")
DB_HOST = os.environ.get("DB_HOST")
DB_NAME = os.environ.get("DB_NAME", "postgres")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASS = os.environ.get("DB_PASS", "password123")

if not SQS_QUEUE_URL:
    raise RuntimeError("SQS_QUEUE_URL is required")

if not DB_HOST:
    raise RuntimeError("DB_HOST is required")

logging.info("Starting fulfillment worker")

# Resolve AWS region the RIGHT way
session = boto3.session.Session()
AWS_REGION = session.region_name

if not AWS_REGION:
    raise RuntimeError(
        "AWS region could not be resolved. "
        "Set AWS_REGION, AWS_DEFAULT_REGION, or configure IAM properly."
    )

logging.info(f"AWS Region: {AWS_REGION}")
logging.info(f"SQS Queue: {SQS_QUEUE_URL}")
logging.info(f"DB Host: {DB_HOST}")

sqs = session.client("sqs")


# Database Connection
def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

# Order Processing Logic
def process_order(message_body: str) -> bool:
    data = json.loads(message_body)

    order_id = data.get("order_id")
    customer_id = data.get("customer_id")
    items = data.get("items", [])

    if not order_id or not items:
        logging.error("Invalid order payload")
        return False

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        logging.info(f"Processing order {order_id}")

        # Prevent duplicate processing
        cur.execute(
            "SELECT 1 FROM orders WHERE order_id = %s",
            (order_id,)
        )
        if cur.fetchone():
            logging.info(f"Order {order_id} already processed")
            conn.rollback()
            return True

        # ACID inventory update
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
                """
                UPDATE inventory
                SET stock = %s
                WHERE item_id = %s AND warehouse_id = %s
                """,
                (new_stock, item["item_id"], item["warehouse_id"])
            )

        # Insert order record
        cur.execute(
            """
            INSERT INTO orders (order_id, customer_id, items)
            VALUES (%s, %s, %s)
            """,
            (order_id, customer_id, json.dumps(items))
        )

        conn.commit()
        logging.info(f"Order {order_id} processed successfully")
        return True

    except Exception as e:
        conn.rollback()
        logging.error(f"Order {order_id} failed: {e}")
        return False

    finally:
        cur.close()
        conn.close()

# Main Worker Loop (NEVER EXIT)
def poll_sqs_forever():
    logging.info("Worker is now polling SQS...")

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
                body = msg["Body"]

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
    poll_sqs_forever()

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
REGION = "us-east-1"

sqs = boto3.client('sqs', region_name=REGION)

def process_order(body):
    data = json.loads(body)
    items = data['items']
    order_id = data['order_id'] # UUID from frontend
    customer_id = data['customer_id']
    
    conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS)
    cursor = conn.cursor()
    
    try:
        print(f"Processing Order {order_id}...")
        # 1. ACID Transaction
        for item in items:
            # Lock Row
            cursor.execute(
                "SELECT stock FROM inventory WHERE item_id=%s AND warehouse_id=%s FOR UPDATE",
                (item['item_id'], item['warehouse_id'])
            )
            row = cursor.fetchone()
            if not row or row[0] < item['quantity']:
                raise Exception(f"Out of stock: {item['item_id']}")
            
            # Decrement
            new_stock = row[0] - item['quantity']
            cursor.execute(
                "UPDATE inventory SET stock=%s WHERE item_id=%s AND warehouse_id=%s",
                (new_stock, item['item_id'], item['warehouse_id'])
            )

        # 2. Insert Order Record
        cursor.execute(
            "INSERT INTO orders (customer_id, status, items) VALUES (%s, %s, %s)",
            (customer_id, 'CONFIRMED', json.dumps(items))
        )
        conn.commit()
        print(f"Order {order_id} SUCCESS.")
        return True
        
    except Exception as e:
        conn.rollback()
        print(f"Order {order_id} FAILED: {e}")
        return False
    finally:
        cursor.close()
        conn.close()

def run_worker():
    print(f"Worker listening on {SQS_QUEUE_URL}")
    while True:
        try:
            # Long Polling (Wait up to 20s for message)
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20
            )
            
            if 'Messages' in response:
                for msg in response['Messages']:
                    receipt_handle = msg['ReceiptHandle']
                    body = msg['Body']
                    
                    if process_order(body):
                        # Delete if successful
                        sqs.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=receipt_handle)
            
        except Exception as e:
            print(f"SQS Error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    run_worker()
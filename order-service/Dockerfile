FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8001 
# Note: expose port 8001 for the Order Service to avoid conflict with Availability (8000)

# Using 1 worker to reduce memory usage on t3.micro
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001", "--workers", "1"]
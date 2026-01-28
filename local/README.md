# Local Development Files

This folder contains files for **local Docker development** (no AWS required).

## Quick Start

```bash
# 1. Start Docker containers
docker-compose -f docker-compose-local.yaml up -d

# 2. Wait for services (about 30 seconds)
docker ps

# 3. Seed the databases
python seed_local.py

# 4. Run Flutter app with local backend
# In rapid_delivery_app/lib/services/api_service.dart:
# Set: useAwsBackend = false
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose-local.yaml` | Docker Compose for PostgreSQL, Redis, OpenSearch |
| `seed_local.py` | Seeds all local databases with test data |
| `add_warehouse_local.py` | Add/list warehouses in local OpenSearch |

## Test Coordinates

Use these in the Flutter app when testing locally:

| City | Latitude | Longitude |
|------|----------|-----------|
| Jaipur | 26.9124 | 75.7873 |
| Delhi | 28.6139 | 77.2090 |
| Mumbai | 19.0760 | 72.8777 |

## Services

| Service | Local URL |
|---------|-----------|
| PostgreSQL | localhost:5432 |
| Redis | localhost:6379 |
| OpenSearch | localhost:9200 |

## Switching to AWS

To switch to AWS backend:
1. Update `rapid_delivery_app/lib/services/api_service.dart`
2. Set `useAwsBackend = true`
3. Run `terraform-files/generate_flutter_config.ps1` to update endpoints

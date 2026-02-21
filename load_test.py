"""
Load Test Script for Rapid Delivery Service
Tests concurrent users hitting the local APIs
"""

import asyncio
import aiohttp
import time
import json
import uuid
from dataclasses import dataclass
from typing import List

# Configuration
BASE_AVAILABILITY_URL = "http://localhost:8000"
BASE_ORDER_URL = "http://localhost:8001"

@dataclass
class TestResult:
    endpoint: str
    status: int
    latency_ms: float
    success: bool
    error: str = ""

async def test_availability(session: aiohttp.ClientSession) -> TestResult:
    """Test stock availability check"""
    url = f"{BASE_AVAILABILITY_URL}/availability?item_id=apple&lat=26.9&lon=75.8"
    start = time.perf_counter()
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
            latency = (time.perf_counter() - start) * 1000
            await resp.json()
            return TestResult("availability", resp.status, latency, resp.status == 200)
    except Exception as e:
        latency = (time.perf_counter() - start) * 1000
        return TestResult("availability", 0, latency, False, str(e))

async def test_products(session: aiohttp.ClientSession) -> TestResult:
    """Test products listing"""
    url = f"{BASE_AVAILABILITY_URL}/products/wh_lnmiit"
    start = time.perf_counter()
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
            latency = (time.perf_counter() - start) * 1000
            await resp.json()
            return TestResult("products", resp.status, latency, resp.status == 200)
    except Exception as e:
        latency = (time.perf_counter() - start) * 1000
        return TestResult("products", 0, latency, False, str(e))

async def test_place_order(session: aiohttp.ClientSession) -> TestResult:
    """Test placing an order"""
    url = f"{BASE_ORDER_URL}/orders"
    order_data = {
        "customer_id": f"test_user_{uuid.uuid4().hex[:8]}",
        "items": [
            {"item_id": "apple", "warehouse_id": "wh_lnmiit", "quantity": 1}
        ]
    }
    start = time.perf_counter()
    try:
        async with session.post(url, json=order_data, timeout=aiohttp.ClientTimeout(total=10)) as resp:
            latency = (time.perf_counter() - start) * 1000
            await resp.json()
            return TestResult("place_order", resp.status, latency, resp.status == 200)
    except Exception as e:
        latency = (time.perf_counter() - start) * 1000
        return TestResult("place_order", 0, latency, False, str(e))

async def test_order_history(session: aiohttp.ClientSession) -> TestResult:
    """Test order history retrieval"""
    url = f"{BASE_ORDER_URL}/orders/test_user"
    start = time.perf_counter()
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
            latency = (time.perf_counter() - start) * 1000
            await resp.json()
            return TestResult("order_history", resp.status, latency, resp.status == 200)
    except Exception as e:
        latency = (time.perf_counter() - start) * 1000
        return TestResult("order_history", 0, latency, False, str(e))

async def run_user_simulation(user_id: int, session: aiohttp.ClientSession) -> List[TestResult]:
    """Simulate a single user's actions"""
    results = []
    
    # User flow: check availability -> view products -> place order
    results.append(await test_availability(session))
    await asyncio.sleep(0.1)  # Small delay between actions
    
    results.append(await test_products(session))
    await asyncio.sleep(0.1)
    
    results.append(await test_place_order(session))
    
    return results

async def run_load_test(concurrent_users: int, iterations: int = 1):
    """Run load test with specified concurrent users"""
    print(f"\n{'='*60}")
    print(f"🧪 LOAD TEST: {concurrent_users} concurrent users, {iterations} iterations")
    print(f"{'='*60}\n")
    
    all_results: List[TestResult] = []
    start_time = time.perf_counter()
    
    connector = aiohttp.TCPConnector(limit=concurrent_users * 2)
    async with aiohttp.ClientSession(connector=connector) as session:
        for iteration in range(iterations):
            tasks = []
            for user_id in range(concurrent_users):
                tasks.append(run_user_simulation(user_id, session))
            
            iteration_results = await asyncio.gather(*tasks)
            for user_results in iteration_results:
                all_results.extend(user_results)
            
            if iterations > 1:
                print(f"  Iteration {iteration + 1}/{iterations} complete")
    
    total_time = time.perf_counter() - start_time
    
    # Analyze results
    analyze_results(all_results, concurrent_users, total_time)

def analyze_results(results: List[TestResult], concurrent_users: int, total_time: float):
    """Analyze and print test results"""
    
    # Group by endpoint
    endpoints = {}
    for r in results:
        if r.endpoint not in endpoints:
            endpoints[r.endpoint] = []
        endpoints[r.endpoint].append(r)
    
    print("\n📊 RESULTS BY ENDPOINT:\n")
    
    total_requests = len(results)
    total_success = sum(1 for r in results if r.success)
    total_failures = total_requests - total_success
    
    for endpoint, endpoint_results in endpoints.items():
        successes = sum(1 for r in endpoint_results if r.success)
        failures = len(endpoint_results) - successes
        latencies = [r.latency_ms for r in endpoint_results if r.success]
        
        if latencies:
            avg_latency = sum(latencies) / len(latencies)
            min_latency = min(latencies)
            max_latency = max(latencies)
            
            # Calculate p50, p95, p99
            sorted_latencies = sorted(latencies)
            p50 = sorted_latencies[int(len(sorted_latencies) * 0.5)]
            p95 = sorted_latencies[int(len(sorted_latencies) * 0.95)] if len(sorted_latencies) > 20 else max_latency
            p99 = sorted_latencies[int(len(sorted_latencies) * 0.99)] if len(sorted_latencies) > 100 else max_latency
        else:
            avg_latency = min_latency = max_latency = p50 = p95 = p99 = 0
        
        status_icon = "✅" if failures == 0 else "⚠️" if failures < len(endpoint_results) * 0.1 else "❌"
        
        print(f"  {status_icon} {endpoint.upper()}")
        print(f"     Requests: {len(endpoint_results)} | Success: {successes} | Failed: {failures}")
        print(f"     Latency:  avg={avg_latency:.0f}ms | min={min_latency:.0f}ms | max={max_latency:.0f}ms")
        print(f"     Percentiles: p50={p50:.0f}ms | p95={p95:.0f}ms | p99={p99:.0f}ms")
        print()
    
    # Print errors if any
    errors = [r for r in results if not r.success]
    if errors:
        print("❌ ERRORS:")
        unique_errors = set(r.error for r in errors if r.error)
        for err in list(unique_errors)[:5]:  # Show first 5 unique errors
            print(f"   • {err[:100]}")
        print()
    
    # Summary
    rps = total_requests / total_time if total_time > 0 else 0
    success_rate = (total_success / total_requests * 100) if total_requests > 0 else 0
    
    print(f"{'='*60}")
    print(f"📈 SUMMARY")
    print(f"{'='*60}")
    print(f"   Concurrent Users:  {concurrent_users}")
    print(f"   Total Requests:    {total_requests}")
    print(f"   Total Time:        {total_time:.2f}s")
    print(f"   Throughput:        {rps:.1f} req/s")
    print(f"   Success Rate:      {success_rate:.1f}%")
    print(f"{'='*60}\n")
    
    # Capacity estimation
    if success_rate >= 99:
        print(f"💪 System handles {concurrent_users} users well!")
        print(f"   Estimated capacity: ~{int(rps * 0.8)} requests/second\n")
    elif success_rate >= 90:
        print(f"⚠️  System under stress with {concurrent_users} users")
        print(f"   Some requests failing - consider scaling\n")
    else:
        print(f"❌ System overloaded with {concurrent_users} users")
        print(f"   Too many failures - reduce load or scale up\n")

async def main():
    print("\n" + "="*60)
    print("🚀 RAPID DELIVERY SERVICE - LOAD TESTER")
    print("="*60)
    
    # Test with increasing load
    for users in [5, 10, 25, 50]:
        await run_load_test(concurrent_users=users, iterations=2)
        await asyncio.sleep(2)  # Cool down between tests

if __name__ == "__main__":
    asyncio.run(main())

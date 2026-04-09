"""Bottleneck routes - demonstrates PERFORMANCE ISSUES for profiling and tracing.

Scenarios:
1. Slow query: Simulates N+1 query problem and unoptimized aggregation
2. CPU bottleneck: Expensive computation loop visible in Pyroscope flamegraphs
3. Memory pressure: Large allocation detectable in profiling
4. Cascading slowness: Multiple slow operations chained together
"""

import hashlib
import random
import time

import structlog
from fastapi import APIRouter, Depends, Query
from opentelemetry import trace
from opentelemetry.trace import SpanKind, StatusCode
from sqlalchemy import func, text
from sqlalchemy.orm import Session

from app.database import get_db
from app.metrics import (
    app_errors_total,
    db_operations_total,
    db_query_duration,
    http_request_duration,
    order_processing_duration,
)
from app.models import Order, Todo, User
from app.schemas import OrderCreate, OrderResponse, ReportResponse

router = APIRouter(prefix="/api/bottleneck", tags=["bottleneck"])
logger = structlog.get_logger()
tracer = trace.get_tracer(__name__)


@router.post("/orders", response_model=OrderResponse, status_code=201)
def create_order(order_in: OrderCreate, user_id: int = 1, db: Session = Depends(get_db)):
    """Create an order with simulated processing delay."""
    start_time = time.time()
    with tracer.start_as_current_span("orders.create", kind=SpanKind.SERVER) as span:
        span.set_attribute("span.type", "order")
        span.set_attribute("order.product", order_in.product_name)
        span.set_attribute("order.user_id", user_id)

        # Simulate order validation (slightly slow)
        with tracer.start_as_current_span("orders.validate", kind=SpanKind.INTERNAL) as val_span:
            time.sleep(random.uniform(0.05, 0.15))
            logger.info("order_validated", product=order_in.product_name)
            val_span.set_status(StatusCode.OK)

        # Simulate inventory check (can be slow)
        with tracer.start_as_current_span("orders.check_inventory", kind=SpanKind.CLIENT) as inv_span:
            inv_span.set_attribute("peer.service", "inventory-service")
            delay = random.uniform(0.1, 0.3)
            time.sleep(delay)
            inv_span.set_attribute("inventory.check_duration_ms", round(delay * 1000, 2))
            logger.info("inventory_checked", product=order_in.product_name, duration_ms=round(delay * 1000, 2))
            inv_span.set_status(StatusCode.OK)

        with tracer.start_as_current_span("db.query.orders.insert", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "INSERT")
            query_start = time.time()
            order = Order(
                user_id=user_id,
                product_name=order_in.product_name,
                quantity=order_in.quantity,
                price=order_in.price,
                status="confirmed",
            )
            db.add(order)
            db.commit()
            db.refresh(order)
            db_query_duration.record(time.time() - query_start, {"operation": "insert", "table": "orders"})
            db_operations_total.add(1, {"operation": "insert", "table": "orders"})
            db_span.set_status(StatusCode.OK)

        duration = time.time() - start_time
        order_processing_duration.record(duration, {"product": order_in.product_name})
        http_request_duration.record(duration, {"endpoint": "/api/bottleneck/orders", "method": "POST", "status": "201"})
        logger.info("order_created", order_id=order.id, duration_ms=round(duration * 1000, 2))
        span.set_status(StatusCode.OK)
        return order


@router.get("/slow-report", response_model=ReportResponse)
def slow_report(user_id: int = 1, db: Session = Depends(get_db)):
    """Generate a report using intentionally SLOW queries (N+1 problem).

    This endpoint demonstrates:
    - N+1 query problem: fetching orders one-by-one instead of batch
    - Expensive aggregation in Python instead of SQL
    - Visible in traces as many small DB spans
    - Visible in profiling as CPU time in Python loops
    """
    start_time = time.time()
    with tracer.start_as_current_span("report.slow_generate", kind=SpanKind.SERVER) as span:
        span.set_attribute("span.type", "bottleneck")
        span.set_attribute("report.user_id", user_id)
        span.set_attribute("report.type", "slow_n_plus_1")

        logger.info("slow_report_started", user_id=user_id)

        # BAD: N+1 query - first get all order IDs, then fetch each one
        with tracer.start_as_current_span("report.fetch_order_ids", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "SELECT")
            query_start = time.time()
            order_ids = db.query(Order.id).filter(Order.user_id == user_id).all()
            db_query_duration.record(time.time() - query_start, {"operation": "select", "table": "orders"})
            db_operations_total.add(1, {"operation": "select", "table": "orders"})
            db_span.set_status(StatusCode.OK)

        orders = []
        # BAD: Fetching each order individually (N+1 problem)
        with tracer.start_as_current_span("report.fetch_orders_n_plus_1", kind=SpanKind.INTERNAL) as n1_span:
            n1_span.set_attribute("report.order_count", len(order_ids))
            for (order_id,) in order_ids:
                with tracer.start_as_current_span(f"db.query.orders.get_{order_id}", kind=SpanKind.CLIENT) as item_span:
                    item_span.set_attribute("db.system", "postgresql")
                    item_span.set_attribute("db.operation", "SELECT")
                    query_start = time.time()
                    order = db.query(Order).filter(Order.id == order_id).first()
                    db_query_duration.record(time.time() - query_start, {"operation": "select", "table": "orders"})
                    db_operations_total.add(1, {"operation": "select", "table": "orders"})
                    item_span.set_status(StatusCode.OK)
                    if order:
                        orders.append(order)
            n1_span.set_status(StatusCode.OK)

        # BAD: Aggregation in Python instead of SQL
        with tracer.start_as_current_span("report.compute_aggregation_python", kind=SpanKind.INTERNAL) as agg_span:
            total_revenue = sum(o.price * o.quantity for o in orders)
            avg_value = total_revenue / len(orders) if orders else 0

            status_counts = {}
            for o in orders:
                status_counts[o.status] = status_counts.get(o.status, 0) + 1

            product_revenue = {}
            for o in orders:
                key = o.product_name
                product_revenue[key] = product_revenue.get(key, 0) + (o.price * o.quantity)

            top_products = sorted(product_revenue.items(), key=lambda x: x[1], reverse=True)[:5]
            top_products_list = [{"product": p, "revenue": r} for p, r in top_products]

            agg_span.set_attribute("report.total_orders", len(orders))
            agg_span.set_attribute("report.total_revenue", total_revenue)
            agg_span.set_status(StatusCode.OK)

        duration = time.time() - start_time
        http_request_duration.record(duration, {"endpoint": "/api/bottleneck/slow-report", "method": "GET", "status": "200"})
        logger.warning(
            "slow_report_completed",
            user_id=user_id,
            order_count=len(orders),
            duration_ms=round(duration * 1000, 2),
            query_count=len(order_ids) + 1,
        )

        span.set_status(StatusCode.OK)
        return ReportResponse(
            total_orders=len(orders),
            total_revenue=round(total_revenue, 2),
            avg_order_value=round(avg_value, 2),
            orders_by_status=status_counts,
            top_products=top_products_list,
        )


@router.get("/cpu-intensive")
def cpu_intensive(iterations: int = Query(default=500000, le=5000000)):
    """CPU-intensive endpoint - visible in Pyroscope flamegraphs.

    Simulates heavy computation that consumes CPU cycles.
    The flamegraph will show time spent in hash computation.
    """
    start_time = time.time()
    with tracer.start_as_current_span("bottleneck.cpu_intensive", kind=SpanKind.SERVER) as span:
        span.set_attribute("span.type", "bottleneck")
        span.set_attribute("bottleneck.iterations", iterations)
        logger.info("cpu_intensive_started", iterations=iterations)

        # Heavy CPU work: nested hash computation
        with tracer.start_as_current_span("bottleneck.hash_computation", kind=SpanKind.INTERNAL) as hash_span:
            result = "seed"
            for i in range(iterations):
                result = hashlib.sha256(result.encode()).hexdigest()
                if i % 100000 == 0:
                    # Periodically do additional work to create interesting flamegraph
                    _fibonacci(25)
            hash_span.set_status(StatusCode.OK)

        duration = time.time() - start_time
        http_request_duration.record(duration, {"endpoint": "/api/bottleneck/cpu-intensive", "method": "GET", "status": "200"})
        logger.warning(
            "cpu_intensive_completed",
            iterations=iterations,
            duration_ms=round(duration * 1000, 2),
        )
        span.set_attribute("bottleneck.duration_ms", round(duration * 1000, 2))
        span.set_status(StatusCode.OK)

        return {
            "status": "completed",
            "iterations": iterations,
            "duration_ms": round(duration * 1000, 2),
            "result_hash": result[:16],
        }


@router.get("/slow-cascade")
def slow_cascade(db: Session = Depends(get_db)):
    """Cascading slow operations - demonstrates trace waterfall visualization.

    Multiple dependent operations each taking time, creating a long trace
    that helps visualize where time is spent in Tempo.
    """
    start_time = time.time()
    with tracer.start_as_current_span("bottleneck.slow_cascade", kind=SpanKind.SERVER) as span:
        span.set_attribute("span.type", "bottleneck")
        logger.info("slow_cascade_started")

        results = {}

        # Step 1: Slow database query with pg_sleep
        with tracer.start_as_current_span("cascade.step1_slow_query", kind=SpanKind.CLIENT) as s1:
            s1.set_attribute("db.system", "postgresql")
            s1.set_attribute("db.operation", "SELECT")
            query_start = time.time()
            try:
                db.execute(text("SELECT pg_sleep(0.5)"))
                results["step1"] = "slow_query_completed"
            except Exception:
                results["step1"] = "slow_query_simulated"
                time.sleep(0.5)
            s1_duration = time.time() - query_start
            db_query_duration.record(s1_duration, {"operation": "slow_query", "table": "synthetic"})
            s1.set_attribute("duration_ms", round(s1_duration * 1000, 2))
            s1.set_status(StatusCode.OK)

        # Step 2: Computation based on step 1
        with tracer.start_as_current_span("cascade.step2_computation", kind=SpanKind.INTERNAL) as s2:
            data = "".join(random.choices("abcdefghijklmnop", k=10000))
            for _ in range(50):
                hashlib.sha512(data.encode()).hexdigest()
            time.sleep(0.2)
            results["step2"] = "computation_completed"
            s2.set_status(StatusCode.OK)

        # Step 3: Another DB query
        with tracer.start_as_current_span("cascade.step3_aggregate_query", kind=SpanKind.CLIENT) as s3:
            s3.set_attribute("db.system", "postgresql")
            s3.set_attribute("db.operation", "SELECT")
            query_start = time.time()
            try:
                count = db.query(func.count(Order.id)).scalar() or 0
                total = db.query(func.sum(Order.price)).scalar() or 0
            except Exception:
                count, total = 0, 0
            db_query_duration.record(time.time() - query_start, {"operation": "aggregate", "table": "orders"})
            results["step3"] = {"order_count": count, "total_value": float(total)}
            s3.set_status(StatusCode.OK)

        # Step 4: Simulated external API call
        with tracer.start_as_current_span("cascade.step4_external_call", kind=SpanKind.CLIENT) as s4:
            time.sleep(random.uniform(0.3, 0.8))
            s4.set_attribute("external.service", "payment-gateway")
            s4.set_attribute("external.status", "success")
            s4.set_attribute("peer.service", "payment-gateway")
            results["step4"] = "external_call_completed"
            s4.set_status(StatusCode.OK)

        duration = time.time() - start_time
        http_request_duration.record(duration, {"endpoint": "/api/bottleneck/slow-cascade", "method": "GET", "status": "200"})
        logger.warning(
            "slow_cascade_completed",
            duration_ms=round(duration * 1000, 2),
            steps=4,
        )
        span.set_attribute("bottleneck.total_duration_ms", round(duration * 1000, 2))
        span.set_status(StatusCode.OK)

        return {"status": "completed", "duration_ms": round(duration * 1000, 2), "steps": results}


def _fibonacci(n: int) -> int:
    """Recursive fibonacci - intentionally inefficient for flamegraph visibility."""
    if n <= 1:
        return n
    return _fibonacci(n - 1) + _fibonacci(n - 2)

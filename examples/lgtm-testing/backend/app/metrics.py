"""Custom Prometheus/OpenTelemetry metrics for application monitoring.

Concepts demonstrated:
- Counter: Monotonically increasing value (e.g., total requests, errors)
- Histogram: Distribution of values (e.g., request latency, query duration)
- UpDownCounter: Value that can increase or decrease (e.g., active connections)
- Gauge (via callback): Point-in-time value (e.g., queue size, memory usage)
"""

from opentelemetry import metrics

meter = metrics.get_meter("lgtm-testing-api", "1.0.0")

# --- Counters ---
# Total HTTP requests by method, endpoint, status
http_requests_total = meter.create_counter(
    name="http_requests_total",
    description="Total number of HTTP requests",
    unit="requests",
)

# Total authentication attempts (success/failure)
auth_attempts_total = meter.create_counter(
    name="auth_attempts_total",
    description="Total authentication attempts",
    unit="attempts",
)

# Total database operations by type (select, insert, update, delete)
db_operations_total = meter.create_counter(
    name="db_operations_total",
    description="Total database operations",
    unit="operations",
)

# Total application errors by type
app_errors_total = meter.create_counter(
    name="app_errors_total",
    description="Total application errors",
    unit="errors",
)

# --- Histograms ---
# HTTP request duration distribution
http_request_duration = meter.create_histogram(
    name="http_request_duration_seconds",
    description="HTTP request duration in seconds",
    unit="s",
)

# Database query duration distribution
db_query_duration = meter.create_histogram(
    name="db_query_duration_seconds",
    description="Database query duration in seconds",
    unit="s",
)

# Order processing duration
order_processing_duration = meter.create_histogram(
    name="order_processing_duration_seconds",
    description="Order processing duration in seconds",
    unit="s",
)

# --- UpDownCounters ---
# Active HTTP connections (goes up and down)
active_connections = meter.create_up_down_counter(
    name="active_connections",
    description="Number of active HTTP connections",
    unit="connections",
)

# Active database sessions
active_db_sessions = meter.create_up_down_counter(
    name="active_db_sessions",
    description="Number of active database sessions",
    unit="sessions",
)

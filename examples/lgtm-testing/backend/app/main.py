"""FastAPI application with full LGTM stack integration.

LGTM Stack:
- Logs    -> Alloy -> Loki     (structured JSON logs with trace_id correlation)
- Traces  -> Alloy -> Tempo    (OpenTelemetry auto + manual instrumentation)
- Metrics -> Alloy -> Prometheus (custom + auto-generated metrics)
- Profiles -> Pyroscope          (continuous CPU/memory profiling)
"""

import os
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import Base, engine
from app.logging_config import setup_logging
from app.metrics import active_connections, http_requests_total
from app.routes import auth, bottleneck, health, seed, todos
from app.telemetry import instrument_app, setup_providers

logger = setup_logging()

# Initialize OTel providers BEFORE app creation so providers exist globally.
# This is safe at module level — it only sets up exporters and providers.
tracer_provider, meter_provider = setup_providers()
logger.info(
    "telemetry_initialized",
    otel_endpoint=settings.otel_exporter_otlp_endpoint,
    service_name=settings.otel_service_name,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle: create DB tables and manage shutdown."""
    # Create database tables
    Base.metadata.create_all(bind=engine)
    logger.info("database_tables_created")

    # Setup Pyroscope profiling
    if settings.pyroscope_enabled:
        try:
            import pyroscope

            # Log package version and native extension status
            pyroscope_version = getattr(pyroscope, "__version__", "unknown")
            logger.info(
                "pyroscope_import_ok",
                version=pyroscope_version,
                module_file=getattr(pyroscope, "__file__", "unknown"),
                available_attrs=[a for a in dir(pyroscope) if not a.startswith("_")],
            )

            # Test HTTP connectivity to Pyroscope server before configuring
            import urllib.request
            import urllib.error

            ready_url = f"{settings.pyroscope_server_address}/ready"
            try:
                req = urllib.request.Request(ready_url, method="GET")
                with urllib.request.urlopen(req, timeout=5) as resp:
                    logger.info(
                        "pyroscope_server_reachable",
                        url=ready_url,
                        status=resp.status,
                        body=resp.read().decode("utf-8", errors="replace")[:200],
                    )
            except urllib.error.URLError as conn_err:
                logger.warning(
                    "pyroscope_server_unreachable",
                    url=ready_url,
                    error=str(conn_err),
                )
            except Exception as conn_err:
                logger.warning(
                    "pyroscope_server_check_failed",
                    url=ready_url,
                    error_type=type(conn_err).__name__,
                    error=str(conn_err),
                )

            # Configure Pyroscope
            configure_args = dict(
                application_name=settings.otel_service_name,
                server_address=settings.pyroscope_server_address,
                tags={
                    "environment": settings.otel_environment,
                    "version": settings.app_version,
                },
            )
            logger.info("pyroscope_configuring", **configure_args)

            pyroscope.configure(**configure_args)

            logger.info(
                "pyroscope_configured",
                server=settings.pyroscope_server_address,
                note="Profiles pushed directly to Pyroscope /ingest (not via Alloy)",
            )
        except ImportError as e:
            logger.warning(
                "pyroscope_not_available",
                reason="pyroscope-io package not installed or native extension failed to load",
                error=str(e),
            )
        except Exception as e:
            logger.warning(
                "pyroscope_init_failed",
                error_type=type(e).__name__,
                error=str(e),
            )
    else:
        logger.info("pyroscope_disabled", hint="Set PYROSCOPE_ENABLED=true to enable")

    yield

    # Shutdown
    tracer_provider.shutdown()
    if meter_provider is not None:
        meter_provider.shutdown()
    logger.info("telemetry_shutdown")


app = FastAPI(
    title="LGTM Testing API",
    description="Application for testing Grafana LGTM Stack (Loki, Grafana, Tempo, Mimir/Prometheus)",
    version=settings.app_version,
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    """Track active connections and request counts."""
    active_connections.add(1)
    try:
        response: Response = await call_next(request)
        http_requests_total.add(
            1,
            {
                "method": request.method,
                "endpoint": request.url.path,
                "status": str(response.status_code),
            },
        )
        return response
    finally:
        active_connections.add(-1)


# Instrument AFTER app creation but BEFORE the server starts.
# This adds the OTel middleware to FastAPI and hooks into SQLAlchemy.
instrument_app(app, engine)

# Register routers
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(todos.router)
app.include_router(bottleneck.router)
app.include_router(seed.router)


@app.get("/debug/pyroscope")
def debug_pyroscope():
    """Diagnostic endpoint to check Pyroscope integration status at runtime."""
    import urllib.request
    import urllib.error

    result = {
        "enabled": settings.pyroscope_enabled,
        "server_address": settings.pyroscope_server_address,
    }

    # Check if pyroscope module is loaded
    try:
        import pyroscope

        result["sdk_loaded"] = True
        result["sdk_version"] = getattr(pyroscope, "__version__", "unknown")
        result["sdk_module"] = getattr(pyroscope, "__file__", "unknown")
    except ImportError as e:
        result["sdk_loaded"] = False
        result["sdk_import_error"] = str(e)

    # Test connectivity to Pyroscope server
    if settings.pyroscope_enabled:
        ready_url = f"{settings.pyroscope_server_address}/ready"
        try:
            req = urllib.request.Request(ready_url, method="GET")
            with urllib.request.urlopen(req, timeout=5) as resp:
                result["server_reachable"] = True
                result["server_status"] = resp.status
        except Exception as e:
            result["server_reachable"] = False
            result["server_error"] = str(e)

    return result


@app.get("/")
def root():
    return {
        "service": settings.app_name,
        "version": settings.app_version,
        "docs": "/docs",
        "endpoints": {
            "health": "/health",
            "ready": "/ready",
            "auth": {
                "register": "POST /api/auth/register",
                "login": "POST /api/auth/login",
            },
            "todos": {
                "list": "GET /api/todos/",
                "create": "POST /api/todos/",
                "get": "GET /api/todos/{id}",
                "update": "PUT /api/todos/{id}",
                "delete": "DELETE /api/todos/{id}",
            },
            "bottleneck": {
                "create_order": "POST /api/bottleneck/orders",
                "slow_report": "GET /api/bottleneck/slow-report",
                "cpu_intensive": "GET /api/bottleneck/cpu-intensive",
                "slow_cascade": "GET /api/bottleneck/slow-cascade",
            },
            "seed": "POST /api/seed/",
        },
    }

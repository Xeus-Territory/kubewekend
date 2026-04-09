"""OpenTelemetry setup: tracing, metrics exporting, and instrumentation."""

import logging

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from pyroscope.otel import PyroscopeSpanProcessor

from app.config import settings

_logger = logging.getLogger(__name__)


def setup_providers():
    """Initialize OpenTelemetry tracer and (optionally) meter providers.

    Must be called before the FastAPI app is created so that
    providers are available for instrumentation.

    Metrics export via OTLP is controlled by OTEL_METRICS_ENABLED.
    When disabled, a no-op MeterProvider is used so custom metrics
    code still works without errors — values are just not exported.
    """
    resource = Resource.create(
        {
            "service.name": settings.otel_service_name,
            "service.version": settings.app_version,
            "deployment.environment": settings.otel_environment,
        }
    )

    # --- Tracing (always enabled) ---
    tracer_provider = TracerProvider(resource=resource)
    span_exporter = OTLPSpanExporter(
        endpoint=settings.otel_exporter_otlp_endpoint,
        insecure=True,
    )
    tracer_provider.add_span_processor(BatchSpanProcessor(span_exporter))
    # --- Pyroscope profiling (optional) ---
    # Set link attributes on spans to correlate with Pyroscope profiles.
    if settings.pyroscope_enabled:
        tracer_provider.add_span_processor(PyroscopeSpanProcessor())
    trace.set_tracer_provider(tracer_provider)

    # --- Metrics (optional) ---
    meter_provider = None
    if settings.otel_metrics_enabled:
        from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
        from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

        metric_exporter = OTLPMetricExporter(
            endpoint=settings.otel_exporter_otlp_endpoint,
            insecure=True,
        )
        metric_reader = PeriodicExportingMetricReader(metric_exporter, export_interval_millis=15000)
        meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
        metrics.set_meter_provider(meter_provider)
        _logger.info("OTLP metrics export enabled -> %s", settings.otel_exporter_otlp_endpoint)
    else:
        # No-op provider: metric instruments work but nothing is exported
        meter_provider = MeterProvider(resource=resource)
        metrics.set_meter_provider(meter_provider)
        _logger.info("OTLP metrics export disabled (set OTEL_METRICS_ENABLED=true to enable)")

    # --- Non-app instrumentation (safe to call early) ---
    LoggingInstrumentor().instrument(set_logging_format=True)

    return tracer_provider, meter_provider


def instrument_app(app, engine):
    """Instrument FastAPI app and SQLAlchemy engine.

    Must be called after app creation but BEFORE the app starts
    (i.e. before uvicorn begins serving).
    """
    FastAPIInstrumentor.instrument_app(app)
    SQLAlchemyInstrumentor().instrument(engine=engine)

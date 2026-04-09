"""Application settings loaded from environment variables."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Application
    app_name: str = "lgtm-testing-api"
    app_version: str = "1.0.0"
    debug: bool = False

    # Database
    database_url: str = "postgresql://appuser:apppassword@postgres:5432/lgtm_testing"

    # OTLP Collector (Alloy)
    otel_exporter_otlp_endpoint: str = "http://alloy.monitoring.svc.cluster.local:4317"
    otel_service_name: str = "lgtm-testing-api"
    otel_environment: str = "development"

    # Metrics export via OTLP (optional - requires Prometheus remote-write or Alloy)
    otel_metrics_enabled: bool = False

    # Pyroscope
    pyroscope_server_address: str = "http://pyroscope.monitoring.svc.cluster.local:4040"
    pyroscope_enabled: bool = True

    model_config = {"env_prefix": "", "case_sensitive": False}


settings = Settings()

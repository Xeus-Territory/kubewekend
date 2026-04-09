"""Authentication routes - demonstrates auth error scenario for LGTM tracing."""

import time

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from opentelemetry import trace
from opentelemetry.trace import SpanKind, StatusCode
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app.database import get_db
from app.metrics import app_errors_total, auth_attempts_total, http_request_duration
from app.models import User
from app.schemas import LoginRequest, LoginResponse, UserCreate, UserResponse

router = APIRouter(prefix="/api/auth", tags=["auth"])
logger = structlog.get_logger()
tracer = trace.get_tracer(__name__)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(user_in: UserCreate, db: Session = Depends(get_db)):
    """Register a new user - normal flow scenario."""
    with tracer.start_as_current_span("auth.register", kind=SpanKind.SERVER) as span:
        span.set_attribute("user.username", user_in.username)
        span.set_attribute("user.email", user_in.email)
        span.set_attribute("span.type", "auth")

        logger.info("user_registration_attempt", username=user_in.username, email=user_in.email)

        # Check existing user
        existing = db.query(User).filter(
            (User.username == user_in.username) | (User.email == user_in.email)
        ).first()
        if existing:
            logger.warning("user_registration_conflict", username=user_in.username)
            app_errors_total.add(1, {"error_type": "registration_conflict", "endpoint": "/api/auth/register"})
            span.set_status(StatusCode.ERROR, "Username or email already exists")
            raise HTTPException(status_code=409, detail="Username or email already exists")

        hashed_password = pwd_context.hash(user_in.password)
        user = User(
            username=user_in.username,
            email=user_in.email,
            hashed_password=hashed_password,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

        logger.info("user_registered_successfully", user_id=user.id, username=user.username)
        span.set_attribute("user.id", user.id)
        span.set_status(StatusCode.OK)
        return user


@router.post("/login", response_model=LoginResponse)
def login(login_req: LoginRequest, db: Session = Depends(get_db)):
    """Login endpoint - demonstrates AUTH ERROR scenario.

    Scenarios:
    - Valid credentials -> success trace
    - Invalid password -> error trace with detailed span events
    - Non-existent user -> error trace
    - Locked account (is_active=False) -> error trace with warning
    """
    start_time = time.time()
    with tracer.start_as_current_span("auth.login", kind=SpanKind.SERVER) as span:
        span.set_attribute("user.username", login_req.username)
        span.set_attribute("span.type", "auth")
        logger.info("login_attempt", username=login_req.username)

        # Step 1: Find user
        with tracer.start_as_current_span("auth.login.find_user", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "SELECT")
            user = db.query(User).filter(User.username == login_req.username).first()
            db_span.set_status(StatusCode.OK)

        if not user:
            duration = time.time() - start_time
            http_request_duration.record(duration, {"endpoint": "/api/auth/login", "status": "404"})
            auth_attempts_total.add(1, {"status": "user_not_found", "username": login_req.username})
            app_errors_total.add(1, {"error_type": "auth_user_not_found", "endpoint": "/api/auth/login"})

            logger.error(
                "login_failed_user_not_found",
                username=login_req.username,
                duration_ms=round(duration * 1000, 2),
            )
            span.set_status(trace.StatusCode.ERROR, "User not found")
            span.record_exception(HTTPException(status_code=401, detail="Invalid credentials"))
            span.add_event("auth.failure", {"reason": "user_not_found", "username": login_req.username})
            raise HTTPException(status_code=401, detail="Invalid credentials")

        # Step 2: Check if account is active
        if not user.is_active:
            duration = time.time() - start_time
            http_request_duration.record(duration, {"endpoint": "/api/auth/login", "status": "403"})
            auth_attempts_total.add(1, {"status": "account_locked", "username": login_req.username})
            app_errors_total.add(1, {"error_type": "auth_account_locked", "endpoint": "/api/auth/login"})

            logger.error(
                "login_failed_account_locked",
                username=login_req.username,
                user_id=user.id,
                duration_ms=round(duration * 1000, 2),
            )
            span.set_status(trace.StatusCode.ERROR, "Account is locked")
            span.record_exception(HTTPException(status_code=403, detail="Account is locked"))
            span.add_event("auth.failure", {"reason": "account_locked", "user_id": user.id})
            raise HTTPException(status_code=403, detail="Account is locked")

        # Step 3: Verify password
        with tracer.start_as_current_span("auth.login.verify_password", kind=SpanKind.INTERNAL) as pwd_span:
            password_valid = pwd_context.verify(login_req.password, user.hashed_password)
            pwd_span.set_attribute("auth.password_valid", password_valid)
            pwd_span.set_status(StatusCode.OK)

        if not password_valid:
            duration = time.time() - start_time
            http_request_duration.record(duration, {"endpoint": "/api/auth/login", "status": "401"})
            auth_attempts_total.add(1, {"status": "invalid_password", "username": login_req.username})
            app_errors_total.add(1, {"error_type": "auth_invalid_password", "endpoint": "/api/auth/login"})

            logger.error(
                "login_failed_invalid_password",
                username=login_req.username,
                user_id=user.id,
                duration_ms=round(duration * 1000, 2),
            )
            span.set_status(trace.StatusCode.ERROR, "Invalid password")
            span.record_exception(HTTPException(status_code=401, detail="Invalid credentials"))
            span.add_event("auth.failure", {"reason": "invalid_password", "user_id": user.id})
            raise HTTPException(status_code=401, detail="Invalid credentials")

        # Success
        duration = time.time() - start_time
        http_request_duration.record(duration, {"endpoint": "/api/auth/login", "status": "200"})
        auth_attempts_total.add(1, {"status": "success", "username": login_req.username})

        logger.info(
            "login_successful",
            username=login_req.username,
            user_id=user.id,
            duration_ms=round(duration * 1000, 2),
        )
        span.set_attribute("user.id", user.id)
        span.add_event("auth.success", {"user_id": user.id})
        span.set_status(StatusCode.OK)

        # Simple token (demo purposes - not for production)
        token = f"demo-token-{user.id}-{user.username}"
        return LoginResponse(
            access_token=token,
            user=UserResponse.model_validate(user),
        )

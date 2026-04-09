"""Seed data route - populates database for testing scenarios."""

import random

import structlog
from fastapi import APIRouter, Depends
from opentelemetry import trace
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Order, Todo, User

router = APIRouter(prefix="/api/seed", tags=["seed"])
logger = structlog.get_logger()
tracer = trace.get_tracer(__name__)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

PRODUCTS = [
    ("Laptop", 999.99),
    ("Keyboard", 79.99),
    ("Mouse", 49.99),
    ("Monitor", 349.99),
    ("Headphones", 129.99),
    ("USB Cable", 12.99),
    ("Webcam", 89.99),
    ("Desk Lamp", 39.99),
]


@router.post("/")
def seed_data(db: Session = Depends(get_db)):
    """Seed the database with test data for all scenarios."""
    with tracer.start_as_current_span("seed.populate"):
        # Create users
        users = []
        test_users = [
            ("alice", "alice@example.com", "password123", True),
            ("bob", "bob@example.com", "password456", True),
            ("charlie", "charlie@example.com", "password789", False),  # Locked account
        ]
        for username, email, password, is_active in test_users:
            existing = db.query(User).filter(User.username == username).first()
            if not existing:
                user = User(
                    username=username,
                    email=email,
                    hashed_password=pwd_context.hash(password),
                    is_active=is_active,
                )
                db.add(user)
                db.flush()
                users.append(user)
                logger.info("seed_user_created", username=username)
            else:
                users.append(existing)

        # Create todos for each active user
        todo_count = 0
        for user in users:
            if not user.is_active:
                continue
            for i in range(5):
                todo = Todo(
                    title=f"Task {i+1} for {user.username}",
                    description=f"Description of task {i+1}",
                    completed=random.choice([True, False]),
                    owner_id=user.id,
                )
                db.add(todo)
                todo_count += 1

        # Create orders for bottleneck testing
        order_count = 0
        statuses = ["pending", "confirmed", "shipped", "delivered", "cancelled"]
        for user in users:
            for _ in range(random.randint(10, 30)):
                product, base_price = random.choice(PRODUCTS)
                order = Order(
                    user_id=user.id,
                    product_name=product,
                    quantity=random.randint(1, 5),
                    price=round(base_price * random.uniform(0.8, 1.2), 2),
                    status=random.choice(statuses),
                )
                db.add(order)
                order_count += 1

        db.commit()
        logger.info("seed_completed", users=len(users), todos=todo_count, orders=order_count)

        return {
            "status": "seeded",
            "users": len(users),
            "todos": todo_count,
            "orders": order_count,
            "test_credentials": [
                {"username": "alice", "password": "password123", "note": "Active user"},
                {"username": "bob", "password": "password456", "note": "Active user"},
                {"username": "charlie", "password": "password789", "note": "LOCKED account - will fail login"},
            ],
        }

"""Pydantic schemas for request/response validation."""

import datetime

from pydantic import BaseModel, EmailStr


# --- User Schemas ---
class UserCreate(BaseModel):
    username: str
    email: str
    password: str


class UserResponse(BaseModel):
    id: int
    username: str
    email: str
    is_active: bool
    created_at: datetime.datetime

    model_config = {"from_attributes": True}


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


# --- Todo Schemas ---
class TodoCreate(BaseModel):
    title: str
    description: str | None = None


class TodoUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    completed: bool | None = None


class TodoResponse(BaseModel):
    id: int
    title: str
    description: str | None
    completed: bool
    owner_id: int
    created_at: datetime.datetime
    updated_at: datetime.datetime

    model_config = {"from_attributes": True}


# --- Order Schemas ---
class OrderCreate(BaseModel):
    product_name: str
    quantity: int = 1
    price: float


class OrderResponse(BaseModel):
    id: int
    user_id: int
    product_name: str
    quantity: int
    price: float
    status: str
    created_at: datetime.datetime

    model_config = {"from_attributes": True}


# --- Report Schemas ---
class ReportResponse(BaseModel):
    total_orders: int
    total_revenue: float
    avg_order_value: float
    orders_by_status: dict[str, int]
    top_products: list[dict]

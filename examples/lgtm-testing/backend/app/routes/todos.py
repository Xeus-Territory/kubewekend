"""Todo routes - demonstrates NORMAL USAGE scenario for LGTM tracing.

Shows clean request -> DB -> response traces with proper span hierarchy.
"""

import time

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from opentelemetry import trace
from opentelemetry.trace import SpanKind, StatusCode
from sqlalchemy.orm import Session

from app.database import get_db
from app.metrics import db_operations_total, db_query_duration, http_request_duration
from app.models import Todo
from app.schemas import TodoCreate, TodoResponse, TodoUpdate

router = APIRouter(prefix="/api/todos", tags=["todos"])
logger = structlog.get_logger()
tracer = trace.get_tracer(__name__)


@router.get("/", response_model=list[TodoResponse])
def list_todos(owner_id: int = 1, skip: int = 0, limit: int = 20, db: Session = Depends(get_db)):
    """List all todos for a user - normal DB read operation."""
    start_time = time.time()
    with tracer.start_as_current_span("todos.list", kind=SpanKind.SERVER) as span:
        span.set_attribute("span.type", "crud")
        span.set_attribute("todos.owner_id", owner_id)
        span.set_attribute("todos.skip", skip)
        span.set_attribute("todos.limit", limit)

        with tracer.start_as_current_span("db.query.todos.list", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "SELECT")
            query_start = time.time()
            todos = db.query(Todo).filter(Todo.owner_id == owner_id).offset(skip).limit(limit).all()
            db_query_duration.record(time.time() - query_start, {"operation": "select", "table": "todos"})
            db_operations_total.add(1, {"operation": "select", "table": "todos"})
            db_span.set_status(StatusCode.OK)

        span.set_attribute("todos.count", len(todos))
        logger.info("todos_listed", owner_id=owner_id, count=len(todos))
        http_request_duration.record(time.time() - start_time, {"endpoint": "/api/todos", "method": "GET", "status": "200"})
        span.set_status(StatusCode.OK)
        return todos


@router.post("/", response_model=TodoResponse, status_code=status.HTTP_201_CREATED)
def create_todo(todo_in: TodoCreate, owner_id: int = 1, db: Session = Depends(get_db)):
    """Create a new todo - normal DB write operation."""
    start_time = time.time()
    with tracer.start_as_current_span("todos.create", kind=SpanKind.SERVER) as span:
        span.set_attribute("span.type", "crud")
        span.set_attribute("todos.title", todo_in.title)
        span.set_attribute("todos.owner_id", owner_id)

        with tracer.start_as_current_span("db.query.todos.insert", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "INSERT")
            query_start = time.time()
            todo = Todo(title=todo_in.title, description=todo_in.description, owner_id=owner_id)
            db.add(todo)
            db.commit()
            db.refresh(todo)
            db_query_duration.record(time.time() - query_start, {"operation": "insert", "table": "todos"})
            db_operations_total.add(1, {"operation": "insert", "table": "todos"})
            db_span.set_status(StatusCode.OK)

        logger.info("todo_created", todo_id=todo.id, title=todo.title, owner_id=owner_id)
        span.set_attribute("todos.id", todo.id)
        http_request_duration.record(time.time() - start_time, {"endpoint": "/api/todos", "method": "POST", "status": "201"})
        span.set_status(StatusCode.OK)
        return todo


@router.get("/{todo_id}", response_model=TodoResponse)
def get_todo(todo_id: int, db: Session = Depends(get_db)):
    """Get a single todo by ID - normal DB read."""
    with tracer.start_as_current_span("todos.get", kind=SpanKind.SERVER) as span:
        span.set_attribute("todos.id", todo_id)
        span.set_attribute("span.type", "crud")

        with tracer.start_as_current_span("db.query.todos.get_by_id", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "SELECT")
            query_start = time.time()
            todo = db.query(Todo).filter(Todo.id == todo_id).first()
            db_query_duration.record(time.time() - query_start, {"operation": "select", "table": "todos"})
            db_operations_total.add(1, {"operation": "select", "table": "todos"})
            db_span.set_status(StatusCode.OK)

        if not todo:
            logger.warning("todo_not_found", todo_id=todo_id)
            span.set_status(StatusCode.ERROR, "Todo not found")
            raise HTTPException(status_code=404, detail="Todo not found")

        logger.info("todo_retrieved", todo_id=todo.id, title=todo.title)
        span.set_status(StatusCode.OK)
        return todo


@router.put("/{todo_id}", response_model=TodoResponse)
def update_todo(todo_id: int, todo_in: TodoUpdate, db: Session = Depends(get_db)):
    """Update a todo - normal DB update operation."""
    with tracer.start_as_current_span("todos.update", kind=SpanKind.SERVER) as span:
        span.set_attribute("todos.id", todo_id)
        span.set_attribute("span.type", "crud")

        with tracer.start_as_current_span("db.query.todos.get_for_update", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "SELECT")
            todo = db.query(Todo).filter(Todo.id == todo_id).first()
            db_operations_total.add(1, {"operation": "select", "table": "todos"})
            db_span.set_status(StatusCode.OK)

        if not todo:
            span.set_status(StatusCode.ERROR, "Todo not found")
            raise HTTPException(status_code=404, detail="Todo not found")

        with tracer.start_as_current_span("db.query.todos.update", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "UPDATE")
            query_start = time.time()
            if todo_in.title is not None:
                todo.title = todo_in.title
            if todo_in.description is not None:
                todo.description = todo_in.description
            if todo_in.completed is not None:
                todo.completed = todo_in.completed
            db.commit()
            db.refresh(todo)
            db_query_duration.record(time.time() - query_start, {"operation": "update", "table": "todos"})
            db_operations_total.add(1, {"operation": "update", "table": "todos"})
            db_span.set_status(StatusCode.OK)

        logger.info("todo_updated", todo_id=todo.id, changes=todo_in.model_dump(exclude_unset=True))
        span.set_status(StatusCode.OK)
        return todo


@router.delete("/{todo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_todo(todo_id: int, db: Session = Depends(get_db)):
    """Delete a todo - normal DB delete operation."""
    with tracer.start_as_current_span("todos.delete", kind=SpanKind.SERVER) as span:
        span.set_attribute("todos.id", todo_id)
        span.set_attribute("span.type", "crud")

        todo = db.query(Todo).filter(Todo.id == todo_id).first()
        if not todo:
            span.set_status(StatusCode.ERROR, "Todo not found")
            raise HTTPException(status_code=404, detail="Todo not found")

        with tracer.start_as_current_span("db.query.todos.delete", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "DELETE")
            query_start = time.time()
            db.delete(todo)
            db.commit()
            db_query_duration.record(time.time() - query_start, {"operation": "delete", "table": "todos"})
            db_operations_total.add(1, {"operation": "delete", "table": "todos"})
            db_span.set_status(StatusCode.OK)

        logger.info("todo_deleted", todo_id=todo_id)
        span.set_status(StatusCode.OK)

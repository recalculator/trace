"""FastAPI surface for the demo application."""

from fastapi import FastAPI, Request

from app.middleware import require_auth
from services.user_service import create_user, find_user
from services.validation import validate_signup_input

app = FastAPI()


@app.post("/auth/signup")
def signup(payload: dict) -> dict:
    """Register a new user and hand back a session token."""
    clean = validate_signup_input(payload)
    result = create_user(clean)
    return {"status": "created", "data": result}


@app.get("/auth/me")
def me(request: Request) -> dict:
    """Return the currently authenticated user."""
    user = require_auth(dict(request.headers))
    return {"status": "ok", "data": user}


@app.get("/users/{email}")
def get_user(email: str) -> dict:
    """Public lookup of a single user."""
    return {"status": "ok", "data": find_user(email)}


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}

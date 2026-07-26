"""User lifecycle orchestration - the heart of the signup flow."""

from repository.user_repository import get_repository
from services.security import hash_password, generate_token


def create_user(payload: dict) -> dict:
    """Create a user from a validated payload and return an auth envelope."""
    password_hash = hash_password(payload["password"], payload["email"])
    record = build_record(payload, password_hash)

    repo = get_repository()
    stored = repo.persist(record)

    token = generate_token(stored["id"], stored["email"])
    return {"user": public_view(stored), "token": token}


def build_record(payload: dict, password_hash: str) -> dict:
    """Assemble the row that will be written to the users table."""
    return {
        "email": payload["email"],
        "display_name": payload["display_name"],
        "password_hash": password_hash,
    }


def public_view(stored: dict) -> dict:
    """Strip secrets from a stored user row before returning it."""
    return {
        "id": stored["id"],
        "email": stored["email"],
        "display_name": stored["display_name"],
    }


def find_user(email: str) -> dict:
    """Fetch a single user by email."""
    repo = get_repository()
    return repo.find_by_email(email)

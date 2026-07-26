"""Request authentication - where auth begins for protected routes."""

from services.security import verify_token
from services.user_service import find_user


class AuthError(Exception):
    """Raised when a request cannot be authenticated."""


def extract_bearer(headers: dict) -> str:
    """Pull the bearer token out of an Authorization header."""
    raw = headers.get("Authorization", "")
    if not raw.startswith("Bearer "):
        raise AuthError("missing bearer token")
    return raw[len("Bearer ") :]


def authenticate_request(headers: dict) -> dict:
    """Authenticate an inbound request and return the current user."""
    token = extract_bearer(headers)
    claims = verify_token(token)
    user = find_user(claims["email"])
    if not user:
        raise AuthError("unknown user")
    return user


def require_auth(headers: dict) -> dict:
    """Dependency used by protected routes."""
    return authenticate_request(headers)

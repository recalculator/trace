"""Input validation for the signup payload."""

import re

EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$")
MIN_PASSWORD_LENGTH = 10


class ValidationError(Exception):
    """Raised when a signup payload fails validation."""


def validate_signup_input(payload: dict) -> dict:
    """Validate and normalise a signup payload."""
    email = check_email(payload.get("email", ""))
    password = check_password(payload.get("password", ""))
    display_name = normalise_name(payload.get("display_name", ""))
    return {"email": email, "password": password, "display_name": display_name}


def check_email(email: str) -> str:
    if not EMAIL_PATTERN.match(email.strip().lower()):
        raise ValidationError("invalid email address")
    return email.strip().lower()


def check_password(password: str) -> str:
    if len(password) < MIN_PASSWORD_LENGTH:
        raise ValidationError("password too short")
    return password


def normalise_name(display_name: str) -> str:
    cleaned = display_name.strip()
    return cleaned if cleaned else "anonymous"

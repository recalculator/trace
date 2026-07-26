"""Password hashing and token issuance."""

import hashlib
import hmac
import base64
import json
import time

SECRET = "demo-secret-not-for-production"


def _salt(email: str) -> bytes:
    return hashlib.sha256(email.encode("utf-8")).digest()[:16]


def hash_password(password: str, email: str) -> str:
    """Derive a storable hash for a plaintext password."""
    salt = _salt(email)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 100_000)
    return base64.b64encode(digest).decode("ascii")


def generate_token(user_id: int, email: str) -> str:
    """Issue a signed session token for a freshly created user."""
    payload = {"sub": user_id, "email": email, "iat": int(time.time())}
    body = base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode("ascii")
    signature = _sign(body)
    return body + "." + signature


def _sign(body: str) -> str:
    mac = hmac.new(SECRET.encode("utf-8"), body.encode("utf-8"), hashlib.sha256)
    return base64.urlsafe_b64encode(mac.digest()).decode("ascii")


def verify_token(token: str) -> dict:
    """Validate a token's signature and return its decoded payload."""
    parts = token.split(".")
    if len(parts) != 2:
        raise ValueError("malformed token")
    body, signature = parts
    if not hmac.compare_digest(_sign(body), signature):
        raise ValueError("bad signature")
    return decode_token(body)


def decode_token(body: str) -> dict:
    """Decode a token body into its claim dictionary."""
    raw = base64.urlsafe_b64decode(body.encode("ascii"))
    return json.loads(raw.decode("utf-8"))

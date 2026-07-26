"""Admin tooling - a second, non-HTTP caller of create_user.

This exists so reverse traversal from `create_user` finds more than just the
signup route: changing `create_user` also breaks the seeding CLI.
"""

from services.user_service import create_user
from services.validation import validate_signup_input

DEMO_USERS = [
    {"email": "ada@example.com", "password": "correct-horse-battery", "display_name": "Ada"},
    {"email": "grace@example.com", "password": "hopper-was-here-42", "display_name": "Grace"},
]


def seed_demo_users() -> list:
    """Create the demo accounts used by the local environment."""
    created = []
    for raw in DEMO_USERS:
        clean = validate_signup_input(raw)
        created.append(create_user(clean))
    return created


def main() -> None:
    for entry in seed_demo_users():
        print("seeded", entry["user"]["email"])


if __name__ == "__main__":
    main()

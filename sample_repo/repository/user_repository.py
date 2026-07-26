"""Persistence boundary for user records."""

from repository.db import execute, query_by


class UserRepository:
    """Stores and retrieves user rows."""

    table = "users"

    def persist(self, user: dict) -> dict:
        """Write a user row to the database."""
        return execute(self.table, user)

    def find_by_email(self, email: str) -> dict:
        """Look a user up by email address."""
        return query_by(self.table, "email", email)


def get_repository() -> UserRepository:
    """Return the repository instance used by the services layer."""
    return UserRepository()

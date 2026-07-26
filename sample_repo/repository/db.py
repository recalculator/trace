"""Toy database layer - an in-memory table with a SQL-ish surface."""

_TABLES: dict = {"users": []}
_SEQUENCE: dict = {"users": 0}


def connect() -> dict:
    """Return a handle to the in-memory database."""
    return {"tables": _TABLES, "sequence": _SEQUENCE}


def next_id(table: str) -> int:
    _SEQUENCE[table] = _SEQUENCE.get(table, 0) + 1
    return _SEQUENCE[table]


def execute(table: str, row: dict) -> dict:
    """Insert a row and return it with its assigned primary key."""
    handle = connect()
    row_id = next_id(table)
    stored = dict(row)
    stored["id"] = row_id
    handle["tables"].setdefault(table, []).append(stored)
    return stored


def query_by(table: str, field: str, value: str) -> dict:
    """Return the first row whose field matches value, or an empty dict."""
    handle = connect()
    for row in handle["tables"].get(table, []):
        if row.get(field) == value:
            return row
    return {}

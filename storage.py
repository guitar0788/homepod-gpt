import os
import sqlite3
import certifi
from contextlib import contextmanager

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS memory (id {identity}, fact TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS history (id {identity}, question TEXT NOT NULL, answer TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS settings (name TEXT PRIMARY KEY, value TEXT NOT NULL)",
    """CREATE TABLE IF NOT EXISTS limits (
        bucket TEXT PRIMARY KEY, count INTEGER NOT NULL
    )""",
)

class Store:
    def __init__(self, connection, local):
        self.connection = connection
        self.local = local

    def execute(self, sql, args=()):
        return self.connection.execute(sql if self.local else sql.replace("%", "%%").replace("?", "%s"), args)

@contextmanager
def database():
    url = os.getenv("DATABASE_URL")
    if url:
        from psycopg import connect
        options = {"sslmode": "verify-full", "sslrootcert": certifi.where(), "connect_timeout": 5}
        if not os.environ.get("RENDER") and os.getenv("LOCAL_POSTGRES_TEST") == "1":
            options = {"connect_timeout": 5}
        connection = connect(url, **options)
        local = False
    elif os.getenv("LOCAL_SQLITE") == "1" and not os.environ.get("RENDER"):
        connection = sqlite3.connect(os.getenv("SQLITE_PATH", "assistant.db"))
        local = True
    else:
        raise RuntimeError("DATABASE_URL required")
    try:
        with connection:
            yield Store(connection, local)
    finally:
        connection.close()

def initialize():
    with database() as db:
        identity = "INTEGER PRIMARY KEY AUTOINCREMENT" if db.local else (
            "BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY"
        )
        for statement in SCHEMA:
            db.execute(statement.format(identity=identity))

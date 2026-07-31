import os
import tempfile

# Point the app at a throwaway SQLite file before it's imported, so tests
# never touch the real Postgres database.
db_fd, db_path = tempfile.mkstemp()
os.environ["DATABASE_URL"] = f"sqlite:///{db_path}"

import pytest
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_create_and_list_todo(client):
    resp = client.post("/todos", json={"title": "Learn Docker"})
    assert resp.status_code == 201
    todo = resp.get_json()
    assert todo["title"] == "Learn Docker"
    assert todo["done"] is False

    resp = client.get("/todos")
    assert resp.status_code == 200
    assert len(resp.get_json()) >= 1


def test_create_todo_without_title(client):
    resp = client.post("/todos", json={})
    assert resp.status_code == 400

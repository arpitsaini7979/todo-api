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


@pytest.mark.parametrize("title", ["", "   ", 123, None, "x" * 201])
def test_create_todo_rejects_invalid_title(client, title):
    resp = client.post("/todos", json={"title": title})
    assert resp.status_code == 400


def test_update_todo_rejects_non_boolean_done(client):
    todo_id = client.post("/todos", json={"title": "Check types"}).get_json()["id"]
    resp = client.put(f"/todos/{todo_id}", json={"done": "yes"})
    assert resp.status_code == 400
    resp = client.put(f"/todos/{todo_id}", json={"done": True})
    assert resp.status_code == 200
    assert resp.get_json()["done"] is True


def test_api_key_enforced_when_configured(client, monkeypatch):
    monkeypatch.setattr("app.API_KEY", "s3cret")
    assert client.get("/todos").status_code == 401
    assert client.get("/todos", headers={"X-API-Key": "wrong"}).status_code == 401
    assert client.get("/todos", headers={"X-API-Key": "s3cret"}).status_code == 200
    # Probes and metrics must stay reachable without the key.
    assert client.get("/health").status_code == 200
    assert client.get("/metrics").status_code == 200

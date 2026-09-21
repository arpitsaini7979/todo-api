import hmac
import os
from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
    "DATABASE_URL", "sqlite:///todo.db"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)

# Exposes a /metrics endpoint with request counts/latencies and process
# stats (including process_start_time_seconds, used for the uptime panel).
metrics = PrometheusMetrics(app)


# Optional shared-secret auth. When API_KEY is set, every /todos request must
# send it in an X-API-Key header. /health and /metrics stay open so probes and
# Prometheus keep working. Unset (the default) leaves the API open, as before.
API_KEY = os.environ.get("API_KEY") or None


@app.before_request
def require_api_key():
    if API_KEY is None or not request.path.startswith("/todos"):
        return None
    supplied = request.headers.get("X-API-Key", "")
    if not hmac.compare_digest(supplied.encode(), API_KEY.encode()):
        return jsonify(error="invalid or missing API key"), 401
    return None


def validate_title(title):
    if not isinstance(title, str) or not title.strip() or len(title) > 200:
        return "title must be a non-empty string of at most 200 characters"
    return None


class Todo(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    done = db.Column(db.Boolean, default=False)

    def to_dict(self):
        return {"id": self.id, "title": self.title, "done": self.done}


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/todos", methods=["GET"])
def get_todos():
    todos = Todo.query.all()
    return jsonify([t.to_dict() for t in todos])


@app.route("/todos", methods=["POST"])
def create_todo():
    data = request.get_json(silent=True) or {}
    if "title" not in data:
        return jsonify(error="title is required"), 400
    error = validate_title(data["title"])
    if error:
        return jsonify(error=error), 400
    todo = Todo(title=data["title"])
    db.session.add(todo)
    db.session.commit()
    return jsonify(todo.to_dict()), 201


@app.route("/todos/<int:todo_id>", methods=["GET"])
def get_todo(todo_id):
    todo = Todo.query.get_or_404(todo_id)
    return jsonify(todo.to_dict())


@app.route("/todos/<int:todo_id>", methods=["PUT"])
def update_todo(todo_id):
    todo = Todo.query.get_or_404(todo_id)
    data = request.get_json(silent=True) or {}
    if "title" in data:
        error = validate_title(data["title"])
        if error:
            return jsonify(error=error), 400
        todo.title = data["title"]
    if "done" in data:
        if not isinstance(data["done"], bool):
            return jsonify(error="done must be a boolean"), 400
        todo.done = data["done"]
    db.session.commit()
    return jsonify(todo.to_dict())


@app.route("/todos/<int:todo_id>", methods=["DELETE"])
def delete_todo(todo_id):
    todo = Todo.query.get_or_404(todo_id)
    db.session.delete(todo)
    db.session.commit()
    return "", 204


with app.app_context():
    db.create_all()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)

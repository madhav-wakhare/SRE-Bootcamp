# Unit Tests for SRE Student API (Database Decoupled)
# ------------------------------------------------------------------------------
# RATIONALE & ARCHITECTURE:
# Standard unit testing best practice requires decoupling application business
# logic tests from physical database dependencies (PostgreSQL / SQLite).
#
# By mocking the SQLAlchemy session layer (`db.session`), these unit tests run
# completely in-memory, providing fast, deterministic, and isolated execution
# that is immune to database container availability, network latency, or schema drift.


from unittest.mock import MagicMock, patch
import pytest
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from src.app import create_app
from src.app.models import Student


@pytest.fixture()
def client():
    """
    Pytest fixture that initializes a isolated Flask test client instance.
    Configures app in TESTING mode without connecting to any physical database engine.
    """
    app = create_app()
    app.config["TESTING"] = True

    with app.test_client() as client:
        yield client

def test_healthcheck(client):
    """
    Verify healthcheck endpoint returns status 200 OK and status JSON.
    Does not require database interaction.
    """
    response = client.get("/healthcheck")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_trace_id_header(client):
    """
    Verify structured log trace ID header ('X-Trace-Id') propagation.
    - Generates a new UUID trace ID if none provided.
    - Preserves and reflects custom incoming 'X-Trace-Id' headers.
    """
    # 1. Test auto-generated trace ID header
    response = client.get("/healthcheck")
    assert response.status_code == 200
    assert "X-Trace-Id" in response.headers
    assert len(response.headers["X-Trace-Id"]) > 0

    # 2. Test explicit trace ID header correlation
    custom_trace_id = "test-trace-id-12345"
    response_custom = client.get("/healthcheck", headers={"X-Trace-Id": custom_trace_id})
    assert response_custom.status_code == 200
    assert response_custom.headers.get("X-Trace-Id") == custom_trace_id


@patch("src.app.routes.db.session")
def test_create_student_success(mock_session, client):
    """
    Test successful student creation with mocked database session.
    Mock strategy:
    - Mock scalar query check for existing student to return None.
    - Mock session.add and session.commit without hitting a real DB.
    """
    # Configure mock session query to report no existing student with the email
    mock_execute = MagicMock()
    mock_execute.scalar_one_or_none.return_value = None
    mock_session.execute.return_value = mock_execute

    payload = {"name": "Alice", "email": "alice@example.com", "age": 20}
    response = client.post("/api/v1/students", json=payload)

    assert response.status_code == 201
    assert response.get_json()["name"] == "Alice"
    assert response.get_json()["email"] == "alice@example.com"
    # Verify session methods were called
    assert mock_session.add.called
    assert mock_session.commit.called


def test_create_student_invalid_payload(client):
    """
    Test student creation validation errors when required fields are missing.
    Validation happens before database call, ensuring early rejection.
    """
    # Missing required field 'age'
    invalid_payload = {"name": "Alice", "email": "alice@example.com"}
    response = client.post("/api/v1/students", json=invalid_payload)

    assert response.status_code == 400
    assert "error" in response.get_json()


@patch("src.app.routes.db.session")
def test_create_student_duplicate_email(mock_session, client):
    """
    Test student creation conflict (HTTP 409) when email already exists.
    Mock strategy:
    - Mock existing student record returned by query.
    """
    existing_student = Student(id=1, name="Alice", email="alice@example.com", age=20)
    mock_execute = MagicMock()
    mock_execute.scalar_one_or_none.return_value = existing_student
    mock_session.execute.return_value = mock_execute

    payload = {"name": "Bob", "email": "alice@example.com", "age": 22}
    response = client.post("/api/v1/students", json=payload)

    assert response.status_code == 409
    assert "already exists" in response.get_json()["error"]


@patch("src.app.routes.db.session")
def test_create_student_integrity_error(mock_session, client):
    """
    Test handling of IntegrityError exception during commit (e.g. race condition duplicate).
    """
    mock_execute = MagicMock()
    mock_execute.scalar_one_or_none.return_value = None
    mock_session.execute.return_value = mock_execute
    # Simulate IntegrityError on commit
    mock_session.commit.side_effect = IntegrityError("duplicate key", None, None)

    payload = {"name": "Charlie", "email": "charlie@example.com", "age": 25}
    response = client.post("/api/v1/students", json=payload)

    assert response.status_code == 409
    assert mock_session.rollback.called


@patch("src.app.routes.db.session")
def test_get_all_students(mock_session, client):
    """
    Test retrieving all students with mocked database result.
    """
    student1 = Student(id=1, name="Alice", email="alice@example.com", age=20)
    student2 = Student(id=2, name="Bob", email="bob@example.com", age=22)

    mock_execute = MagicMock()
    mock_execute.scalars.return_value.all.return_value = [student1, student2]
    mock_session.execute.return_value = mock_execute

    response = client.get("/api/v1/students")

    assert response.status_code == 200
    data = response.get_json()
    assert len(data) == 2
    assert data[0]["name"] == "Alice"
    assert data[1]["name"] == "Bob"


@patch("src.app.routes.db.session")
def test_get_student_by_id_success(mock_session, client):
    """
    Test retrieving a specific student by ID when present.
    """
    student = Student(id=1, name="Alice", email="alice@example.com", age=20)
    mock_session.get.return_value = student

    response = client.get("/api/v1/students/1")

    assert response.status_code == 200
    assert response.get_json()["email"] == "alice@example.com"
    mock_session.get.assert_called_once_with(Student, 1)


@patch("src.app.routes.db.session")
def test_get_student_by_id_not_found(mock_session, client):
    """
    Test retrieving a non-existent student ID returns HTTP 404.
    """
    mock_session.get.return_value = None

    response = client.get("/api/v1/students/999")

    assert response.status_code == 404
    assert "Student not found" in response.get_json()["error"]



@patch("src.app.routes.db.session")
def test_update_student_success(mock_session, client):
    """
    Test successful student update.
    """
    student = Student(id=1, name="Alice", email="alice@example.com", age=20)
    mock_session.get.return_value = student

    mock_execute = MagicMock()
    mock_execute.scalar_one_or_none.return_value = None
    mock_session.execute.return_value = mock_execute

    update_payload = {"name": "Alice Updated", "age": 21}
    response = client.put("/api/v1/students/1", json=update_payload)

    assert response.status_code == 200
    assert response.get_json()["name"] == "Alice Updated"
    assert response.get_json()["age"] == 21
    assert mock_session.commit.called


@patch("src.app.routes.db.session")
def test_update_student_not_found(mock_session, client):
    """
    Test update fails with HTTP 404 if student does not exist.
    """
    mock_session.get.return_value = None

    response = client.put("/api/v1/students/999", json={"name": "Nobody"})

    assert response.status_code == 404


@patch("src.app.routes.db.session")
def test_delete_student_success(mock_session, client):
    """
    Test successful student deletion.
    """
    student = Student(id=1, name="Alice", email="alice@example.com", age=20)
    mock_session.get.return_value = student

    response = client.delete("/api/v1/students/1")

    assert response.status_code == 200
    assert response.get_json()["message"] == "Student deleted"
    mock_session.delete.assert_called_once_with(student)
    assert mock_session.commit.called


@patch("src.app.routes.db.session")
def test_delete_student_not_found(mock_session, client):
    """
    Test deletion returns HTTP 404 when student ID is missing.
    """
    mock_session.get.return_value = None

    response = client.delete("/api/v1/students/999")

    assert response.status_code == 404

import os

import pytest

from src.app import create_app


@pytest.fixture()
def client(tmp_path):
    # pytest fixture: reusable setup code that runs before each test.
    # tmp_path gives us a temporary folder for a fresh test database.
    db_path = tmp_path / "students.db"
    os.environ["DATABASE_URL"] = f"sqlite:///{db_path}"
    
    # Import the database instance to initialize the schema for testing
    from src.app.models import db
    from src.app import create_app
    app = create_app()
    app.config["TESTING"] = True
    
    # Run schema creation in the test application context
    with app.app_context():
        db.create_all() # Create the database schema (tables) for testing
        
    with app.test_client() as client:
        yield client # Provide the test client to the test functions for making HTTP requests to the Flask app


def test_healthcheck(client):
    # A simple test to verify the health endpoint responds correctly.
    response = client.get("/healthcheck")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"


def test_student_crud_flow(client):
    # This test covers the full CRUD flow: create, read, update, delete.
    create_response = client.post(
        "/api/v1/students",
        json={"name": "Alice", "email": "alice@example.com", "age": 20},
    )
    assert create_response.status_code == 201
    student = create_response.get_json()
    assert student["name"] == "Alice"
    assert student["id"] == 1

    list_response = client.get("/api/v1/students")
    assert list_response.status_code == 200
    students = list_response.get_json()
    assert len(students) == 1

    get_response = client.get("/api/v1/students/1")
    assert get_response.status_code == 200
    assert get_response.get_json()["email"] == "alice@example.com"

    update_response = client.put(
        "/api/v1/students/1",
        json={"name": "Alice Updated", "email": "alice.updated@example.com", "age": 21},
    )
    assert update_response.status_code == 200
    assert update_response.get_json()["name"] == "Alice Updated"

    delete_response = client.delete("/api/v1/students/1")
    assert delete_response.status_code == 200
    assert delete_response.get_json()["message"] == "Student deleted"

    after_delete = client.get("/api/v1/students/1")
    assert after_delete.status_code == 404


def test_duplicate_student_email(client):
    # Create first student
    response1 = client.post(
        "/api/v1/students",
        json={"name": "Alice", "email": "alice@example.com", "age": 20},
    )
    assert response1.status_code == 201

    # Attempt to create second student with duplicate email
    response2 = client.post(
        "/api/v1/students",
        json={"name": "Bob", "email": "alice@example.com", "age": 22},
    )
    assert response2.status_code == 409
    assert "already exists" in response2.get_json()["error"]

    # Create second student with unique email
    response3 = client.post(
        "/api/v1/students",
        json={"name": "Bob", "email": "bob@example.com", "age": 22},
    )
    assert response3.status_code == 201
    bob_id = response3.get_json()["id"]

    # Attempt to update Bob's email to Alice's email
    response4 = client.put(
        f"/api/v1/students/{bob_id}",
        json={"name": "Bob Updated", "email": "alice@example.com", "age": 23},
    )
    assert response4.status_code == 409
    assert "already exists" in response4.get_json()["error"]


def test_trace_id_header(client):
    # Test that requests return an X-Trace-Id header
    response = client.get("/healthcheck")
    assert response.status_code == 200
    assert "X-Trace-Id" in response.headers
    trace_id = response.headers["X-Trace-Id"]
    assert len(trace_id) > 0

    # Test that passing an X-Trace-Id header returns the same trace ID
    custom_trace_id = "test-trace-id-12345"
    response2 = client.get("/healthcheck", headers={"X-Trace-Id": custom_trace_id})
    assert response2.status_code == 200
    assert response2.headers.get("X-Trace-Id") == custom_trace_id


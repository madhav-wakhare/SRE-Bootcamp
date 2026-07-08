import logging
from flask import Blueprint, jsonify, request
from sqlalchemy.exc import SQLAlchemyError, IntegrityError
from src.app.models import db, Student

logger = logging.getLogger(__name__)

# Define blueprint for API routing
api_bp = Blueprint("api", __name__)

@api_bp.get("/healthcheck")
def healthcheck():
    logger.info("Healthcheck successful")
    return jsonify({"status": "ok"}), 200 # Return a JSON response indicating the health status of the application

@api_bp.post("/api/v1/students")
def create_student():
    data = request.get_json(silent=True) or {} # Get the JSON payload from the request body, or use an empty dictionary if the payload is invalid or missing
    if not data.get("name") or not data.get("email") or data.get("age") is None:
        logger.warning("Invalid student payload")
        return jsonify({"error": "name, email and age are required"}), 400

    # Gracefully handle check if student with the same email already exists
    existing_student = db.session.execute(db.select(Student).filter_by(email=data["email"])).scalar_one_or_none()
    if existing_student:
        logger.warning("Conflict: Student with email %s already exists", data["email"])
        return jsonify({"error": "Student with this email already exists"}), 409

    # Create a new Student instance with the provided data
    student = Student(name=data["name"], email=data["email"], age=data["age"])
    try:
        db.session.add(student) # Add the new student to the database session
        db.session.commit() # Commit the session to save the new student to the database
        logger.info("Created student %s", student.id) # Log the creation of the new student with their ID
        return jsonify(student.to_dict()), 201 # Return a JSON response with the newly created student's data and a 201 Created status code
    # Handle integrity constraint violation (e.g. duplicate key)
    except IntegrityError:
        db.session.rollback()
        logger.warning("Conflict: Duplicate email insertion attempted during creation")
        return jsonify({"error": "Student with this email already exists"}), 409
    # Handle other SQLAlchemy errors that occur during the database operations
    except SQLAlchemyError as exc:
        db.session.rollback() # Roll back the session to undo any changes made during the failed transaction
        logger.exception("Failed to create student")
        return jsonify({"error": str(exc)}), 500 # Return a JSON response with the error message and a 500 Internal Server Error status code

# Define the API endpoint to retrieve all students from the database
@api_bp.get("/api/v1/students")
def get_students():
    # Retrieve all students from the database using SQLAlchemy 2.0 select syntax
    students = db.session.execute(db.select(Student)).scalars().all()
    return jsonify([student.to_dict() for student in students]), 200 # Return a JSON response with the list of students and a 200 OK status code

# Define the API endpoint to retrieve a specific student by their ID from the database
@api_bp.get("/api/v1/students/<int:student_id>")
def get_student(student_id):
    # Retrieve a specific student by their ID using db.session.get (replaces deprecated Student.query.get)
    student = db.session.get(Student, student_id)
    if not student:
        return jsonify({"error": "Student not found"}), 404
    return jsonify(student.to_dict()), 200 # Return a JSON response with the student's data and a 200 OK status code

# Define the API endpoint to update a specific student's information in the database
@api_bp.put("/api/v1/students/<int:student_id>")
def update_student(student_id):
    # Retrieve the student by their ID from the database
    student = db.session.get(Student, student_id)
    if not student:
        return jsonify({"error": "Student not found"}), 404

    # Get the JSON payload from the request body, or use an empty dictionary if the payload is invalid or missing
    data = request.get_json(silent=True) or {}

    # Gracefully handle check if the new email belongs to another existing student
    new_email = data.get("email")
    if new_email and new_email != student.email:
        existing_student = db.session.execute(db.select(Student).filter_by(email=new_email)).scalar_one_or_none()
        if existing_student:
            logger.warning("Conflict: Student with email %s already exists", new_email)
            return jsonify({"error": "Student with this email already exists"}), 409

    # Update the student's attributes with the provided data, or keep the existing values if not provided
    student.name = data.get("name", student.name)
    student.email = data.get("email", student.email)
    student.age = data.get("age", student.age)
    try:
        db.session.commit() # Commit the session to save the updated student information to the database
        logger.info("Updated student %s", student.id)
        return jsonify(student.to_dict()), 200 # Return a JSON response with the updated student's data and a 200 OK status code
    # Handle integrity constraint violation (e.g. duplicate key)
    except IntegrityError:
        db.session.rollback()
        logger.warning("Conflict: Duplicate email update attempted")
        return jsonify({"error": "Student with this email already exists"}), 409
    except SQLAlchemyError as exc:
        db.session.rollback()
        logger.exception("Failed to update student")
        return jsonify({"error": str(exc)}), 500

# Define the API endpoint to delete a specific student from the database
@api_bp.delete("/api/v1/students/<int:student_id>")
def delete_student(student_id):
    # Retrieve the student by their ID from the database
    student = db.session.get(Student, student_id)
    if not student:
        return jsonify({"error": "Student not found"}), 404

    try:
        db.session.delete(student)
        db.session.commit()
        logger.info("Deleted student %s", student.id)
        return jsonify({"message": "Student deleted"}), 200
    except SQLAlchemyError as exc:
        db.session.rollback()
        logger.exception("Failed to delete student")
        return jsonify({"error": str(exc)}), 500

import os
import logging
from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.exc import SQLAlchemyError
from dotenv import load_dotenv

# Load environment variables from .env file if present
load_dotenv()

# Configure standard logging to output meaningful information
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# SQLAlchemy is acts as a bridge between the Python application and the database, allowing for ORM capabilities and database-agnostic operations (No Raw Queries)
db = SQLAlchemy()

# Define the Student database model at module-level to make it easily importable and reusable
class Student(db.Model):
    __tablename__ = "students" # Define the table name in the database
    id = db.Column(db.Integer, primary_key=True) # Unique ID for each student (primary key)
    name = db.Column(db.String(100), nullable=False) # Name of the student (cannot be null)
    email = db.Column(db.String(120), unique=True, nullable=False) # Unique email address (cannot be null)
    age = db.Column(db.Integer, nullable=False) # Age of the student (cannot be null)

    def to_dict(self):
        # Convert the Student object to a dictionary for easy JSON serialization
        return {"id": self.id, "name": self.name, "email": self.email, "age": self.age}


def create_app():
    app = Flask(__name__) # Create a Flask application instance
    # Get the database URL from environment variable or use a default PostgreSQL string for production parity (falling back to SQLite for local development/tests)
    db_url = os.getenv("DATABASE_URL")
    
    # If we are in test environment, allow using SQLite for self-contained testing
    if app.config.get("TESTING"):
        db_url = os.getenv("DATABASE_URL")

    app.config["SQLALCHEMY_DATABASE_URI"] = db_url # Configure the SQLAlchemy database URI
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False # Disable SQLAlchemy event system to save resources
    db.init_app(app) # Initialize the SQLAlchemy instance with the Flask app

    # Define the API endpoints for the Flask application
    @app.get("/healthcheck")
    def healthcheck():
        logger.info("Healthcheck successful")
        return jsonify({"status": "ok"}), 200 # Return a JSON response indicating the health status of the application

    @app.post("/api/v1/students")
    def create_student():
        data = request.get_json(silent=True) or {} # Get the JSON payload from the request body, or use an empty dictionary if the payload is invalid or missing
        if not data.get("name") or not data.get("email") or data.get("age") is None:
            logger.warning("Invalid student payload")
            return jsonify({"error": "name, email and age are required"}), 400

        # Create a new Student instance with the provided data
        student = Student(name=data["name"], email=data["email"], age=data["age"])
        try:
            db.session.add(student) # Add the new student to the database session
            db.session.commit() # Commit the session to save the new student to the database
            logger.info("Created student %s", student.id) # Log the creation of the new student with their ID
            return jsonify(student.to_dict()), 201 # Return a JSON response with the newly created student's data and a 201 Created status code
        # Handle any SQLAlchemy errors that occur during the database operations
        except SQLAlchemyError as exc:
            db.session.rollback() # Roll back the session to undo any changes made during the failed transaction
            logger.exception("Failed to create student")
            return jsonify({"error": str(exc)}), 500 # Return a JSON response with the error message and a 500 Internal Server Error status code

    # Define the API endpoint to retrieve all students from the database
    @app.get("/api/v1/students")
    def get_students():
        # Retrieve all students from the database using SQLAlchemy 2.0 select syntax
        students = db.session.execute(db.select(Student)).scalars().all()
        return jsonify([student.to_dict() for student in students]), 200 # Return a JSON response with the list of students and a 200 OK status code

    # Define the API endpoint to retrieve a specific student by their ID from the database
    @app.get("/api/v1/students/<int:student_id>")
    def get_student(student_id):
        # Retrieve a specific student by their ID using db.session.get (replaces deprecated Student.query.get)
        student = db.session.get(Student, student_id)
        if not student:
            return jsonify({"error": "Student not found"}), 404
        return jsonify(student.to_dict()), 200 # Return a JSON response with the student's data and a 200 OK status code

    # Define the API endpoint to update a specific student's information in the database
    @app.put("/api/v1/students/<int:student_id>")
    def update_student(student_id):
        # Retrieve the student by their ID from the database
        student = db.session.get(Student, student_id)
        if not student:
            return jsonify({"error": "Student not found"}), 404

        # Get the JSON payload from the request body, or use an empty dictionary if the payload is invalid or missing
        data = request.get_json(silent=True) or {}
        # Update the student's attributes with the provided data, or keep the existing values if not provided
        student.name = data.get("name", student.name)
        student.email = data.get("email", student.email)
        student.age = data.get("age", student.age)
        try:
            db.session.commit() # Commit the session to save the updated student information to the database
            logger.info("Updated student %s", student.id)
            return jsonify(student.to_dict()), 200 # Return a JSON response with the updated student's data and a 200 OK status code
        except SQLAlchemyError as exc:
            db.session.rollback()
            logger.exception("Failed to update student")
            return jsonify({"error": str(exc)}), 500

    # Define the API endpoint to delete a specific student from the database
    @app.delete("/api/v1/students/<int:student_id>")
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

    return app


# Create the application instance
app = create_app()


if __name__ == "__main__":
    # Get port from environment variable or default to 5000 to support dynamic port binding
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)

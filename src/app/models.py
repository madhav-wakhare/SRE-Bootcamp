from flask_sqlalchemy import SQLAlchemy

# db = SQLAlchemy() is created inside models.py without any reference to an app object. This allows your database models (like Student) to import and use db.
db = SQLAlchemy()

class Student(db.Model):
    __tablename__ = "students" # Explicitly define the table name as 'students'

    # Define the fields (columns) of the student table
    id = db.Column(db.Integer, primary_key=True) # Unique ID for each student, acts as primary key
    name = db.Column(db.String(100), nullable=False) # Student's name, cannot be empty
    email = db.Column(db.String(120), unique=True, nullable=False) # Student's email, must be unique across all students, cannot be empty
    age = db.Column(db.Integer, nullable=False) # Student's age, cannot be empty

    # Serializer method to convert student database records to a Python dictionary format
    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "email": self.email,
            "age": self.age
        }

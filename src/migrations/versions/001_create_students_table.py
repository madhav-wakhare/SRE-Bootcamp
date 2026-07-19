"""Create students table

Revision ID: 001_create_students_table
Revises: 
Create Date: 2026-07-19 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# Revision identifiers used by Alembic
revision: str = '001_create_students_table'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Apply migration: Create the 'students' table if it does not already exist.
    Defines columns: id (Primary Key), name (NOT NULL), email (UNIQUE, NOT NULL), age (NOT NULL).
    """
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if not inspector.has_table("students"):
        op.create_table(
            'students',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('name', sa.String(length=100), nullable=False),
            sa.Column('email', sa.String(length=120), nullable=False),
            sa.Column('age', sa.Integer(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('email')
        )


def downgrade() -> None:
    """
    Revert migration: Drop the 'students' table if it exists.
    """
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if inspector.has_table("students"):
        op.drop_table('students')

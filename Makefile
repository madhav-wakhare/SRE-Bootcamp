.PHONY: install run test migrate

install:
	python3 -m pip install -r requirements.txt

migrate:
	python3 migrations/apply_migrations.py

run:
	python3 app.py

test:
	PYTHONPATH=. pytest -q

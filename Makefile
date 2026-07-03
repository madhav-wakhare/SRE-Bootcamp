IMAGE_NAME ?= sre-student-api
IMAGE_VERSION ?= 1.0.0

.PHONY: install run test migrate docker-build docker-run

install:
	python3 -m pip install -r requirements.txt

migrate:
	python3 migrations/apply_migrations.py

run:
	python3 app.py

test:
	PYTHONPATH=. pytest -q

docker-build:
	docker build -t $(IMAGE_NAME):$(IMAGE_VERSION) .

docker-run:
	docker run --rm -p 5000:5000 --env-file .env $(IMAGE_NAME):$(IMAGE_VERSION)

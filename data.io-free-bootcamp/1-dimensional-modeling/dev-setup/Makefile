include example.env
SHELL := /bin/bash

.PHONY: up down restart inspect

up:
	@if [[ ! -f .env ]]; then \
		echo "Warning: File .env does not exists. Using example.env"; \
		cp example.env .env; \
	fi;
	docker compose up -d;

down:
	docker compose down --volumes
	@if [[ "$(docker ps -f name=${DOCKER_CONTAINER})" ]]; then \
		echo "Terminating running container"; \
		docker rm ${DOCKER_CONTAINER}; \
	fi; \

restart:
	docker compose down -v;
	sleep 3;
	docker compose up -d;

logs:
	docker logs ${DOCKER_CONTAINER};

inspect:
	docker inspect ${DOCKER_CONTAINER} | grep "Source"

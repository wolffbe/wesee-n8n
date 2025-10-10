CONTAINER_NAME = n8n
VOLUME_NAME = n8n_data

# Default to Docker Hub image; optionally override at runtime:
#   make start IMAGE_NAME=docker.n8n.io/n8nio/n8n
IMAGE_NAME ?= n8nio/n8n
FALLBACK_IMAGE = n8nio/n8n

OS := $(shell uname 2>/dev/null || echo Windows)

ifeq ($(OS), Windows)
    PWD_CMD = cd
    MKDIR_CMD = if not exist "$(WESEE_DIR)" mkdir "$(WESEE_DIR)"
    RMDIR_CMD = if exist "$(WESEE_DIR)" rmdir /S /Q "$(WESEE_DIR)"
else
    PWD_CMD = pwd
    MKDIR_CMD = mkdir -p $(WESEE_DIR)
    RMDIR_CMD = rm -rf $(WESEE_DIR)
endif

CURRENT_DIR := $(shell $(PWD_CMD))
WESEE_DIR := $(CURRENT_DIR)/wesee

ENV_VARS = -e N8N_DIAGNOSTICS_ENABLED=false \
           -e N8N_VERSION_NOTIFICATIONS_ENABLED=false \
           -e N8N_TEMPLATES_ENABLED=false \
           -e EXTERNAL_FRONTEND_HOOKS_URLS= \
           -e N8N_DIAGNOSTICS_CONFIG_FRONTEND= \
           -e N8N_DIAGNOSTICS_CONFIG_BACKEND= \
           -e N8N_RUNNERS_ENABLED=true \
           -e N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=false

check-volume:
	@if ! docker volume inspect $(VOLUME_NAME) >/dev/null 2>&1; then \
		echo "Creating Docker volume $(VOLUME_NAME)..."; \
		docker volume create $(VOLUME_NAME); \
	else \
		echo "Docker volume $(VOLUME_NAME) already exists."; \
	fi

ensure-wesee-dir:
	@$(MKDIR_CMD)
	@echo "Ensured wesee directory exists: $(WESEE_DIR)"

install: check-volume ensure-wesee-dir
	@echo "n8n installation setup complete."

start: ## Start n8n in detached mode (auto-fallback image)
	@echo "Starting n8n..."
	@if docker ps -q -f name=$(CONTAINER_NAME) >/dev/null 2>&1 && [ -n "$$(docker ps -q -f name=$(CONTAINER_NAME))" ]; then \
		echo "n8n is already running. Container ID:"; \
		docker ps -q -f name=$(CONTAINER_NAME); \
	else \
		IMAGE=$$(docker manifest inspect $(IMAGE_NAME) >/dev/null 2>&1 && echo "$(IMAGE_NAME)" || echo "$(FALLBACK_IMAGE)"); \
		echo "Using image: $$IMAGE"; \
		docker run -d $(ENV_VARS) --name $(CONTAINER_NAME) -p 5678:5678 \
			-v $(VOLUME_NAME):/home/node/.n8n \
			-v $(WESEE_DIR):/home/node/wesee $$IMAGE; \
	fi

startfg: ## Start n8n in foreground mode (auto-fallback image)
	@echo "Starting n8n in foreground mode..."
	@if docker ps -q -f name=$(CONTAINER_NAME) >/dev/null 2>&1 && [ -n "$$(docker ps -q -f name=$(CONTAINER_NAME))" ]; then \
		echo "n8n is already running. Container ID:"; \
		docker ps -q -f name=$(CONTAINER_NAME); \
	else \
		IMAGE=$$(docker manifest inspect $(IMAGE_NAME) >/dev/null 2>&1 && echo "$(IMAGE_NAME)" || echo "$(FALLBACK_IMAGE)"); \
		echo "Using image: $$IMAGE"; \
		docker run -it --rm $(ENV_VARS) --name $(CONTAINER_NAME) -p 5678:5678 \
			-v $(VOLUME_NAME):/home/node/.n8n \
			-v $(WESEE_DIR):/home/node/wesee $$IMAGE; \
	fi

stop:
	@echo "Stopping n8n..."
	-@docker stop $(CONTAINER_NAME) >/dev/null 2>&1 || true
	-@docker rm $(CONTAINER_NAME) >/dev/null 2>&1 || true

imwf: ensure-wesee-dir
	@echo "Cleaning /home/node/wesee directory in container..."
	docker exec -it $(CONTAINER_NAME) rm -rf /home/node/wesee/workflows/*

	@echo "Copying workflow files to container..."
	docker cp $(WESEE_DIR)/workflows/. $(CONTAINER_NAME):/home/node/wesee/workflows

	@echo "Importing workflows into n8n..."
	docker exec -it $(CONTAINER_NAME) n8n import:workflow --separate --input=/home/node/wesee/workflows

imcr: ensure-wesee-dir
	@echo "Cleaning /home/node/wesee directory in container..."
	docker exec -it $(CONTAINER_NAME) rm -rf /home/node/wesee/credentials/*

	@echo "Copying credential files to container..."
	docker cp $(WESEE_DIR)/credentials/. $(CONTAINER_NAME):/home/node/wesee/credentials

	@echo "Importing credentials into n8n..."
	docker exec -it $(CONTAINER_NAME) n8n import:credentials --separate --input=/home/node/wesee/credentials

im: imcr imwf

exwf: ensure-wesee-dir
	@echo "Clearing the workflows folder inside the container..."
	docker exec -it $(CONTAINER_NAME) sh -c "rm -rf /home/node/wesee/workflows*"

	@echo "Exporting workflows inside container using backup format..."
	docker exec -it $(CONTAINER_NAME) n8n export:workflow --backup --output=/home/node/wesee/workflows

	@echo "Cleaning 'pinData' and renaming files based on workflow name inside the container..."
	docker exec -it $(CONTAINER_NAME) sh -c '\
		for file in /home/node/wesee/workflows/*.json; do \
			cleaned=$$(mktemp); \
			jq "walk(if type == \"object\" then del(.pinData) else . end)" $$file > $$cleaned; \
			name=$$(jq -r .name $$cleaned); \
			safe_name=$$(echo "$$name" | sed "s/[\/:*?\"<>|]/-/g"); \
			mv $$cleaned "/home/node/wesee/workflows/$$safe_name.json"; \
			rm -f $$file; \
		done'

	@echo "Copying cleaned and renamed workflows to host machine..."
	docker cp $(CONTAINER_NAME):/home/node/wesee/workflows $(WESEE_DIR)

excr: ensure-wesee-dir
	@echo "Clearing the credentials folder inside the container..."
	docker exec -it $(CONTAINER_NAME) sh -c "rm -rf /home/node/wesee/credentials*"

	@echo "Exporting all credentials..."
	docker exec -it $(CONTAINER_NAME) n8n export:credentials --backup --output=/home/node/wesee/credentials

	@echo "Renaming credential files to name_type.json format..."
	docker exec -it $(CONTAINER_NAME) sh -c '\
		for file in /home/node/wesee/credentials/*.json; do \
			name=$$(jq -r .name $$file); \
			type=$$(jq -r .type $$file); \
			safe_name=$$(echo "$$name" | sed "s/[\/:*?\"<>|]/-/g"); \
			safe_type=$$(echo "$$type" | sed "s/[\/:*?\"<>|]/-/g"); \
			new_name="/home/node/wesee/credentials/$${safe_name}_$${safe_type}.json"; \
			mv $$file $$new_name; \
		done'

	@echo "Copying credentials to host machine..."
	docker cp $(CONTAINER_NAME):/home/node/wesee/credentials $(WESEE_DIR)

excrd: ensure-wesee-dir
	@echo "Clearing the credentials folder inside the container..."
	docker exec -it $(CONTAINER_NAME) sh -c "rm -rf /home/node/wesee/credentials*"

	@echo "Exporting decrypted credentials inside container..."
	docker exec -it $(CONTAINER_NAME) n8n export:credentials --backup --decrypted --output=/home/node/wesee/credentials

	@echo "Renaming credential files to name_type.json format..."
	docker exec -it $(CONTAINER_NAME) sh -c '\
		for file in /home/node/wesee/credentials/*.json; do \
			name=$$(jq -r .name $$file); \
			type=$$(jq -r .type $$file); \
			safe_name=$$(echo "$$name" | sed "s/[\/:*?\"<>|]/-/g"); \
			safe_type=$$(echo "$$type" | sed "s/[\/:*?\"<>|]/-/g"); \
			new_name="/home/node/wesee/credentials/$${safe_name}_$${safe_type}.json"; \
			mv $$file $$new_name; \
		done'

	@echo "Copying decrypted credentials to host machine..."
	docker cp $(CONTAINER_NAME):/home/node/wesee/credentials $(WESEE_DIR)

ex: excr exwf

exd: exwf excrd

remove:
	@echo "Removing n8n setup (container, volumes, image)..."
	@echo "Stopping and removing container (if it exists)..."
	-@docker rm -f $(CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Removing Docker volume (if it exists): $(VOLUME_NAME)"
	-@docker volume rm $(VOLUME_NAME) >/dev/null 2>&1 || true
	@echo "Removing image(s) (if they exist): $(IMAGE_NAME) and $(FALLBACK_IMAGE)"
	-@docker image rm $(IMAGE_NAME) >/dev/null 2>&1 || true
	-@docker image rm $(FALLBACK_IMAGE) >/dev/null 2>&1 || true
	@echo "Removal complete."

.PHONY: install check-volume ensure-wesee-dir start startfg stop im imwf imcr ex exwf excr excrd exd remove

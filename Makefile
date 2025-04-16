.PHONY: setup start stop restart backup restore update logs clean help

SHELL := /bin/bash
SCRIPTS_DIR := ./scripts
BACKUP_FILE ?= $(shell ls -t backups/n8n_backup_*.tar.gz 2>/dev/null | head -1)

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@egrep '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'

setup: ## Run initial setup
	@echo -e "$(GREEN)Setting up n8n...$(NC)"
	@chmod +x $(SCRIPTS_DIR)/*.sh
	@$(SCRIPTS_DIR)/setup.sh

start: ## Start all services
	@echo -e "$(GREEN)Starting n8n...$(NC)"
	@docker compose up -d
	@echo -e "$(GREEN)Services started. n8n is available at http://localhost:5678$(NC)"

stop: ## Stop all services
	@echo -e "$(YELLOW)Stopping n8n...$(NC)"
	@docker compose down
	@echo -e "$(GREEN)Services stopped.$(NC)"

restart: stop start ## Restart all services

backup: ## Create a backup
	@echo -e "$(GREEN)Creating backup...$(NC)"
	@$(SCRIPTS_DIR)/backup.sh
	@echo -e "$(GREEN)Backup created.$(NC)"

restore: ## Restore from the most recent backup (or specify BACKUP_FILE=path/to/backup.tar.gz)
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo -e "$(RED)No backup file found. Please specify BACKUP_FILE=path/to/backup.tar.gz$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(YELLOW)Restoring from backup: $(BACKUP_FILE)$(NC)"
	@$(SCRIPTS_DIR)/restore.sh $(BACKUP_FILE)
	@echo -e "$(GREEN)Restore completed.$(NC)"

update: ## Update n8n and/or PostgreSQL versions (N8N_VERSION=x.x.x POSTGRES_VERSION=x.x.x-alpine)
	@echo -e "$(YELLOW)Updating services...$(NC)"
	@N8N_VERSION_ARG=""; \
	POSTGRES_VERSION_ARG=""; \
	if [ ! -z "$(N8N_VERSION)" ]; then \
		N8N_VERSION_ARG="-n $(N8N_VERSION)"; \
	fi; \
	if [ ! -z "$(POSTGRES_VERSION)" ]; then \
		POSTGRES_VERSION_ARG="-p $(POSTGRES_VERSION)"; \
	fi; \
	$(SCRIPTS_DIR)/update.sh $$N8N_VERSION_ARG $$POSTGRES_VERSION_ARG
	@echo -e "$(GREEN)Update completed.$(NC)"

logs: ## View logs (SERVICE=n8n or postgres, LINES=100)
	@SERVICE=$${SERVICE:-""}; \
	LINES=$${LINES:-100}; \
	if [ -z "$$SERVICE" ]; then \
		docker compose logs --tail=$$LINES; \
	else \
		docker compose logs --tail=$$LINES $$SERVICE; \
	fi

setup-cron: ## Set up automated backups
	@echo -e "$(YELLOW)Setting up automated backups...$(NC)"
	@$(SCRIPTS_DIR)/setup-cron.sh
	@echo -e "$(GREEN)Automated backups set up.$(NC)"

clean: ## Remove all containers, volumes, and networks
	@echo -e "$(RED)WARNING: This will remove all data. Are you sure? [y/N]$(NC)"
	@read -r response; \
	if [[ $$response =~ ^([yY][eE][sS]|[yY])$$ ]]; then \
		echo -e "$(YELLOW)Removing all containers, volumes, and networks...$(NC)"; \
		docker compose down -v; \
		echo -e "$(GREEN)Cleanup completed.$(NC)"; \
	else \
		echo -e "$(GREEN)Aborted.$(NC)"; \
	fi

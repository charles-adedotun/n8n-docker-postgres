# n8n Workflow Automation Platform - Localhost Setup

This project provides a reliable, secure n8n installation with PostgreSQL for data persistence, designed specifically for self-hosting on localhost environments.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Management Scripts](#management-scripts)
- [Backup and Recovery](#backup-and-recovery)
- [Updating](#updating)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

## Features

- Complete n8n setup with PostgreSQL database for localhost use
- Docker-based deployment for consistency and isolation
- Automated backup and recovery procedures
- Secure configuration with credentials management via Docker secrets
- Resource limiting for stability
- Health monitoring
- Easy update process
- Bind mounts for improved data persistence and management

## Requirements

- Docker and Docker Compose
- macOS (tested) or Linux environment on your local machine
- 2GB+ RAM recommended
- 10GB+ free disk space

## Installation

1. Clone this repository or download and extract it to your desired location on your local machine.

2. Navigate to the project directory:
   ```bash
   cd n8n-project
   ```

   Note: A `.gitignore` file is included that excludes sensitive files like `.env`, backup files, logs, and temporary files. If you're using Git for version control, be sure to review the `.gitignore` file.

3. Copy the example environment file and modify it to set your desired configuration:
   ```bash
   # Copy the example file
   cp .env.example .env
   
   # Use your favorite editor to customize it
   nano .env
   ```

4. Make the scripts executable:
   ```bash
   chmod +x scripts/*.sh
   ```

5. Run the setup script using one of these methods:
   ```bash
   # Using the script directly
   ./scripts/setup.sh
   
   # OR using the Makefile
   make setup
   ```

6. Access n8n in your browser at `http://localhost:5678`.

### Using the Makefile

This project includes a Makefile to simplify managing your localhost n8n installation:

```bash
# View all available commands
make help

# Start all services
make start

# Stop all services
make stop

# Restart all services
make restart

# Create a backup
make backup

# Restore from a backup
make restore BACKUP_FILE=backups/n8n_backup_20250410_123456.tar.gz

# Update versions
make update N8N_VERSION=latest POSTGRES_VERSION=14.17-alpine

# View logs
make logs SERVICE=n8n LINES=100

# Set up automated backups on your local machine
make setup-cron

# Clean up everything (removes all data)
make clean
```

## Configuration

### Environment Variables

The following environment variables can be configured in the `.env` file:

| Variable | Description | Default |
|----------|-------------|---------|  
| `N8N_VERSION` | Version of n8n to use | `latest` |
| `POSTGRES_VERSION` | Version of PostgreSQL to use | `14.17-alpine` |
| `N8N_HOST` | Hostname where n8n will be accessible | `localhost` |
| `N8N_PROTOCOL` | Protocol (http or https) | `http` |
| `POSTGRES_DB` | PostgreSQL database name | `n8n` |
| `POSTGRES_USER` | PostgreSQL username | `n8n_user` |
| `POSTGRES_PASSWORD` | PostgreSQL password | `change_me_in_production` |
| `N8N_ENCRYPTION_KEY` | Encryption key for sensitive data | `change_me_in_production_with_32+_characters` |
| `TIMEZONE` | Timezone for the application | `UTC` |
| `BACKUP_RETENTION_DAYS` | Number of days to keep backups | `7` |

### Resource Limits and Reservations

Resource limits are configured in the `docker-compose.yml` file. The default settings are:

- n8n: 
  - Limits: 1GB RAM, 1 CPU
  - Reservations: 256MB RAM, 0.2 CPU
- PostgreSQL: 
  - Limits: 1GB RAM, 0.5 CPU
  - Reservations: 128MB RAM, 0.1 CPU

Adjust these values based on your server capabilities and workload requirements.

### Data Persistence

Data is stored in the following locations:

- n8n data: `./data/n8n`
- PostgreSQL data: `./data/postgres`

These directories are created during setup and mounted as bind mounts for improved data persistence and easier management.

## Management Scripts

The project includes several management scripts in the `scripts/` directory:

### setup.sh

Initial setup script that:
- Checks for Docker and Docker Compose
- Validates environment variables
- Generates secure random credentials
- Creates required directories and secrets
- Starts the services
- Verifies successful startup

Usage:
```bash
./scripts/setup.sh
```

### backup.sh

Creates backups of the PostgreSQL database and n8n data:
- Generates timestamped backup files
- Compresses backups to save space
- Implements retention policy to remove old backups
- Provides detailed logging
- Backs up both container data and bind mounts

Usage:
```bash
./scripts/backup.sh
```

### restore.sh

Restores n8n and PostgreSQL data from a backup file:
- Stops running services
- Restores PostgreSQL database
- Restores n8n configuration
- Restarts services
- Verifies successful restoration

Usage:
```bash
./scripts/restore.sh /path/to/backup/n8n_backup_20250410_123456.tar.gz
```

### update.sh

Safely updates n8n and PostgreSQL to new versions:
- Creates a backup before updating
- Updates Docker images
- Restarts services
- Verifies successful update

Usage:
```bash
./scripts/update.sh -n latest -p 14.17-alpine
```

Options:
- `-n, --n8n VERSION`: Update n8n to the specified version
- `-p, --postgres VERSION`: Update PostgreSQL to the specified version

### setup-cron.sh

Sets up automated backups every 6 hours:
- Creates a cron job (Linux) or launchd task (macOS)
- Configures log rotation
- Runs at 00:00, 06:00, 12:00, and 18:00 by default

Usage:
```bash
./scripts/setup-cron.sh
```

## Backup and Recovery

### Automated Backups

To set up automated backups on your local machine that run every 6 hours:

```bash
./scripts/setup-cron.sh
```

This will create a job that runs the backup script at 00:00, 06:00, 12:00, and 18:00 every day.

### Manual Backups

To create a backup manually:

```bash
./scripts/backup.sh
```

Backup files are stored in the `backups/` directory with timestamped filenames (e.g., `n8n_backup_20250410_123456.tar.gz`).

### Restoring from Backup

To restore from a backup:

```bash
./scripts/restore.sh backups/n8n_backup_20250410_123456.tar.gz
```

## Updating

To update n8n to the latest version on your localhost installation:

```bash
./scripts/update.sh -n latest
```

To update PostgreSQL to a specific version:

```bash
./scripts/update.sh -p 14.17-alpine
```

To update both:

```bash
./scripts/update.sh -n latest -p 14.17-alpine
```

**Note:** Major PostgreSQL version upgrades (e.g., 14.x to 15.x) may require additional steps. The script will warn you in such cases.

## Security Considerations

### Passwords and Encryption Keys

- The setup script automatically generates strong random passwords and encryption keys
- Database password is stored as a Docker secret for improved security
- All sensitive information is stored in the `.env` file and `.secrets` directory
- The `.env` file permissions are set to 600 (readable only by the owner)
- The `.secrets` directory permissions are set to 700 (accessible only by the owner)

### Network Isolation

The services are configured with a dedicated Docker network for isolation, with a specific subnet for predictable addressing.

### Resource Limits

Resource limits and reservations are set to prevent resource exhaustion and ensure service availability.

### Logging Configuration

All containers have log rotation configured to prevent log files from consuming too much disk space.

## Troubleshooting

### Checking Logs

To view logs for the services:

```bash
# View n8n logs
docker compose logs n8n

# View PostgreSQL logs
docker compose logs postgres

# Follow logs in real-time
docker compose logs -f n8n
```

### Common Issues

**n8n fails to start**

- Check if PostgreSQL is running:
  ```bash
  docker compose ps
  ```
- Verify database connection settings in `.env`
- Check n8n logs for specific errors

**Backup fails**

- Ensure the backup directory is writable
- Check available disk space
- View the backup log at `logs/backup.log`

**Restore fails**

- Verify the backup file exists and is valid
- Check the restore log for specific errors
- Ensure you have sufficient permissions

**Update fails**

- Create a manual backup before retrying
- Check compatibility between n8n version and PostgreSQL version
- View the update log for specific errors

**Data persistence issues**

- Check if the data directories exist and have the correct permissions
- Verify that the bind mounts are properly configured in `docker-compose.yml`
- Ensure the user running Docker has permission to access the data directories

## Final Notes

This setup provides a robust n8n environment on your local machine, with all the tools needed for backup, recovery, and maintenance. If you encounter any issues not covered by the troubleshooting section, check the n8n documentation or community forums for additional support.

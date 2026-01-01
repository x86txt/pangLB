# Pangolin Tunnel Ingress Load Balancing Healthcheck
## with guidance on how to build it out using Cloudflare Load Balancing or Cron
A lightweight health check server designed for monitoring of Pangolin (Newt) tunnel services. This service checks for the presence of a health file and returns HTTP 200 (OK) or 503 (Service Unavailable) accordingly, enabling Cloudflare (or the service of your choice) to perform health-based load balancing across multiple tunnel instances.

## Features

- **Health File Monitoring**: Checks for the presence of a health file (default: `/run/newt/healthy`)
- **File Age Validation**: Optional maximum age check to ensure the health file is recently updated
- **Cloudflare Integration**: Returns appropriate HTTP status codes (200/503) for Cloudflare health monitors
- **Optional Systemd Integration**: Can optionally check systemd unit status
- **TLS Support**: Optional TLS/HTTPS support for secure monitoring
- **Graceful Shutdown**: Handles SIGINT and SIGTERM signals gracefully
- **JSON Health Endpoint**: Provides detailed health status in JSON format

## Installation

<!-- Installation instructions will be provided here -->

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LISTEN_ADDR` | `:8443` | Address and port to listen on |
| `NEWT_HEALTH_FILE` | `/run/newt/healthy` | Path to the health file to monitor |
| `MAX_AGE` | `2m` | Maximum age for the health file (e.g., `2m`, `30s`) |
| `TLS_CERT_FILE` | - | Path to TLS certificate file (enables HTTPS if set) |
| `TLS_KEY_FILE` | - | Path to TLS private key file (enables HTTPS if set) |
| `CHECK_SYSTEMD` | `false` | Enable systemd unit status check (`true`/`false`) |
| `SYSTEMD_UNIT` | `newt` | Systemd unit name to check (if `CHECK_SYSTEMD=true`) |
| `SYSTEMD_TIMEOUT` | `1s` | Timeout for systemd check |
| `PORT` | - | Alternative way to set port (sets `LISTEN_ADDR=:PORT`) |

## Usage

### Basic Usage

Run the health check server with default settings:

```bash
./panglb
```

The server will listen on `:8443` and check for `/run/newt/healthy`.

### Custom Health File Path

```bash
NEWT_HEALTH_FILE=/custom/path/healthy ./panglb
```

### With TLS

```bash
TLS_CERT_FILE=/path/to/cert.pem TLS_KEY_FILE=/path/to/key.pem ./panglb
```

### With Systemd Check

```bash
CHECK_SYSTEMD=true SYSTEMD_UNIT=newt ./panglb
```

### Custom Listen Address

```bash
LISTEN_ADDR=:8080 ./panglb
```

Or using the PORT variable:

```bash
PORT=8080 ./panglb
```

## API Endpoints

### GET /healthz

Health check endpoint that returns JSON with detailed status.

**Response (200 OK):**

```json
{
  "ok": true,
  "now": "2024-01-15T10:30:00Z",
  "checks": {
    "newt_health_file": {
      "ok": true,
      "message": "present"
    }
  }
}
```

**Response (503 Service Unavailable):**

```json
{
  "ok": false,
  "now": "2024-01-15T10:30:00Z",
  "checks": {
    "newt_health_file": {
      "ok": false,
      "message": "health file missing"
    }
  }
}
```

### GET /

Simple endpoint that returns `ok\n` with HTTP 200 status.

## Building

### Build for Linux AMD64

```bash
GOOS=linux GOARCH=amd64 go build -o panglb main.go
```

### Build for Current Platform

```bash
go build -o panglb main.go
```

## Health File Format

The health file is a simple marker file. The program checks:

1. File exists
2. File is not a directory
3. File modification time is within `MAX_AGE` (if configured)

To create a health file:

```bash
touch /run/newt/healthy
```

To update the health file (useful for periodic health checks):

```bash
touch /run/newt/healthy
```

## Cloudflare Integration

Configure a Cloudflare health monitor to check the `/healthz` endpoint. Cloudflare will:

- Treat HTTP 200 responses as healthy
- Treat HTTP 503 responses as unhealthy
- Route traffic only to healthy instances

## License

<!-- License information will be added here -->

# Graceful Shutdown Implementation

This document describes the graceful shutdown implementation for the Sanbase Phoenix application, designed to handle Kubernetes pod termination properly.

## Overview

When a Kubernetes pod is terminated, it sends a SIGTERM signal to the container. Our implementation ensures that:

1. **New requests are stopped** - The Phoenix endpoint is shut down to prevent new connections
2. **Existing requests complete** - Running GraphQL queries and other requests are allowed to finish
3. **Timeout protection** - If requests don't complete within 30 seconds, the application is forcefully shut down
4. **Proper cleanup** - All resources are properly cleaned up before shutdown

## Components

### 1. GracefulShutdown GenServer

**File**: `lib/sanbase/graceful_shutdown.ex`

This is the main coordinator for graceful shutdown:

- Listens for SIGTERM and SIGINT signals
- Tracks active requests
- Manages the shutdown sequence
- Enforces timeout limits

Key functions:
- `request_started/0` - Called when a new request begins
- `request_finished/0` - Called when a request completes
- `get_active_requests_count/0` - Returns current active request count

### 2. RequestTracker Plug

**File**: `lib/sanbase_web/plug/request_tracker.ex`

This plug tracks HTTP requests:

- Automatically called for all requests through the endpoint pipeline
- Increments request counter when request starts
- Decrements request counter when request finishes
- Uses `register_before_send/2` to ensure tracking even if request fails

### 3. Health Controller

**File**: `lib/sanbase_web/controllers/health_controller.ex`

Provides health check endpoint for Kubernetes:

- `/health` endpoint returns application status
- Includes active request count for monitoring
- Used by Kubernetes liveness and readiness probes

### 4. Server Script

**File**: `rel/overlays/bin/server`

Enhanced server startup script:

- Properly handles SIGTERM signals
- Manages application lifecycle
- Provides additional timeout protection at the shell level

## How It Works

### Startup Sequence

1. `Sanbase.GracefulShutdown` starts first in the supervision tree
2. Signal handlers are registered for SIGTERM and SIGINT
3. Request tracking is initialized

### Normal Operation

1. Each HTTP request goes through `SanbaseWeb.Plug.RequestTracker`
2. Request counter is incremented at start
3. Request counter is decremented at completion
4. Health endpoint reports current active request count

### Shutdown Sequence

When SIGTERM is received:

1. **Signal Handling**: `GracefulShutdown` receives the signal
2. **Stop New Requests**: Phoenix endpoint is stopped via `Phoenix.Endpoint.stop/1`
3. **Wait for Completion**: System waits for active requests to finish
4. **Timeout Protection**: 30-second timer starts
5. **Force Shutdown**: If timeout reached, `Application.stop(:sanbase)` is called
6. **Process Exit**: `System.halt(0)` ensures clean exit

## Configuration

### Kubernetes Deployment

The Kubernetes deployment should include:

```yaml
spec:
  template:
    spec:
      containers:
      - name: sanbase
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "echo 'PreStop hook: Starting graceful shutdown'"]
        terminationGracePeriodSeconds: 60  # Longer than internal 30s timeout
        livenessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 5
          periodSeconds: 5
```

### Environment Variables

No additional environment variables are required. The implementation uses:

- `MIX_ENV=prod` - Standard Phoenix environment
- `PHX_SERVER=true` - Enables Phoenix server mode

## Monitoring

### Health Endpoint

The `/health` endpoint returns:

```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "active_requests": 5
}
```

### Logs

Key log messages to monitor:

- `"Graceful shutdown handler started"` - System initialized
- `"Received SIGTERM signal, starting graceful shutdown"` - Shutdown initiated
- `"Stopping Phoenix endpoint to prevent new requests"` - New requests blocked
- `"Waiting for X active requests to complete"` - Waiting for completion
- `"All requests completed, shutting down"` - Clean shutdown
- `"Graceful shutdown timeout reached, forcing shutdown"` - Timeout occurred

## Testing

### Local Testing

1. Start the application:
   ```bash
   mix phx.server
   ```

2. Send SIGTERM signal:
   ```bash
   pkill -TERM -f "beam.smp"
   ```

3. Monitor logs for graceful shutdown sequence

### Kubernetes Testing

1. Deploy the application
2. Scale down the deployment:
   ```bash
   kubectl scale deployment sanbase-web --replicas=0
   ```
3. Monitor pod logs for graceful shutdown

## Troubleshooting

### Common Issues

1. **Requests not completing**: Check for long-running queries or database connections
2. **Timeout too short**: Increase the 30-second timeout in `GracefulShutdown`
3. **Endpoint not stopping**: Verify Phoenix endpoint is properly configured
4. **Process hanging**: Check for external service connections that don't timeout

### Debugging

1. Enable debug logging in the application
2. Monitor the `/health` endpoint for active request count
3. Check Kubernetes events for pod termination issues
4. Review application logs for shutdown sequence

## Best Practices

1. **Keep requests short**: Long-running requests may not complete within timeout
2. **Use timeouts**: All external service calls should have appropriate timeouts
3. **Monitor health**: Use the health endpoint for Kubernetes probes
4. **Test regularly**: Verify graceful shutdown works in your environment
5. **Document changes**: Update this document when modifying shutdown behavior

## Future Enhancements

Potential improvements:

1. **Database connection cleanup**: Ensure all database connections are properly closed
2. **External service cleanup**: Gracefully close connections to external services
3. **Metrics collection**: Track shutdown metrics for monitoring
4. **Configurable timeouts**: Make timeout values configurable via environment
5. **WebSocket handling**: Add specific handling for WebSocket connections 
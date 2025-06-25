#!/bin/bash

# Test script for graceful shutdown functionality
# This script starts the application and then sends SIGTERM to test graceful shutdown

set -e

echo "Starting Sanbase application for graceful shutdown test..."

# Start the application in the background
mix phx.server &
APP_PID=$!

echo "Application started with PID: $APP_PID"

# Wait for the application to start
echo "Waiting for application to start..."
sleep 10

# Check if the application is running
if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "Application failed to start"
    exit 1
fi

echo "Application is running. Starting some test requests..."

# Start some background requests to simulate active load
for i in {1..5}; do
    curl -s http://localhost:4000/health > /dev/null &
    echo "Started request $i"
done

# Wait a moment for requests to be processed
sleep 2

echo "Sending SIGTERM signal to test graceful shutdown..."
kill -TERM "$APP_PID"

echo "Waiting for graceful shutdown to complete..."
timeout 60 tail --pid="$APP_PID" -f /dev/null || true

# Check if the application has stopped
if kill -0 "$APP_PID" 2>/dev/null; then
    echo "Application is still running after timeout, forcing shutdown..."
    kill -KILL "$APP_PID"
    sleep 2
fi

echo "Graceful shutdown test completed."
echo "Check the application logs for shutdown sequence messages." 
#!/bin/bash
set -e

echo "[WARP] Starting Cloudflare WARP..."

# Start the WARP daemon
warp-svc &
WARP_PID=$!

# Wait for the daemon to be ready
echo "[WARP] Waiting for WARP daemon to start..."
for i in {1..15}; do
    if warp-cli status &>/dev/null; then
        break
    fi
    sleep 1
done

# Register if not already registered
STATUS=$(warp-cli status 2>&1 || true)
if echo "$STATUS" | grep -q "Registration missing"; then
    echo "[WARP] Registering device..."
    warp-cli registration new
    echo "[WARP] Accepting terms..."
    warp-cli registration accept
fi

# Configure proxy mode on port 4000
echo "[WARP] Enabling proxy mode on port 4000..."
warp-cli mode proxy
warp-cli proxy port 4000
warp-cli connect

# Wait for connection
echo "[WARP] Waiting for WARP connection..."
for i in {1..30}; do
    STATUS=$(warp-cli status 2>&1 || true)
    if echo "$STATUS" | grep -q "Connected"; then
        echo "[WARP] Connected! Proxy available at 127.0.0.1:4000"
        break
    fi
    sleep 1
done

# Verify proxy is working
STATUS=$(warp-cli status 2>&1 || true)
if ! echo "$STATUS" | grep -q "Connected"; then
    echo "[WARP] WARNING: WARP may not be fully connected. Continuing anyway..."
fi

# Execute the main command
echo "[WARP] Starting application..."
exec "$@"

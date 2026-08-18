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
        echo "[WARP] Daemon is ready"
        break
    fi
    sleep 1
done

# Register
echo "[WARP] Registering device..."
REG_OUTPUT=$(warp-cli registration new 2>&1) || true
echo "[WARP] Registration output: $REG_OUTPUT"

# Configure proxy mode on port 4000
echo "[WARP] Enabling proxy mode on port 4000..."
MODE_OUTPUT=$(warp-cli mode proxy 2>&1) || true
echo "[WARP] Mode output: $MODE_OUTPUT"

PORT_OUTPUT=$(warp-cli proxy port 4000 2>&1) || true
echo "[WARP] Port output: $PORT_OUTPUT"

CONNECT_OUTPUT=$(warp-cli connect 2>&1) || true
echo "[WARP] Connect output: $CONNECT_OUTPUT"

# Wait for connection
echo "[WARP] Waiting for WARP connection..."
for i in {1..30}; do
    STATUS=$(warp-cli status 2>&1 || true)
    echo "[WARP] Status check $i: $STATUS"
    if echo "$STATUS" | grep -qi "connected"; then
        echo "[WARP] Connected! Proxy available at 127.0.0.1:4000"
        break
    fi
    sleep 1
done

# Final status
STATUS=$(warp-cli status 2>&1 || true)
if ! echo "$STATUS" | grep -qi "connected"; then
    echo "[WARP] WARNING: WARP may not be fully connected. Continuing anyway..."
fi

# Execute the main command
echo "[WARP] Starting application..."
exec "$@"

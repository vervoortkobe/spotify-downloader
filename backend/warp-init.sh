#!/bin/bash
set -e

echo "[WARP] Initializing system services..."

# Ensure D-Bus system daemon is running for warp-svc IPC
mkdir -p /run/dbus
if [ -f /var/run/dbus/pid ]; then
    rm -f /var/run/dbus/pid
fi
if [ -f /run/dbus/pid ]; then
    rm -f /run/dbus/pid
fi
dbus-daemon --config-file=/usr/share/dbus-1/system.conf --fork 2>/dev/null || true

# Create TUN device if it doesn't exist
if [ ! -c /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 600 /dev/net/tun 2>/dev/null || true
fi

echo "[WARP] Starting Cloudflare WARP daemon..."
warp-svc &
WARP_PID=$!

# Wait for the daemon to be ready
echo "[WARP] Waiting for WARP daemon to respond..."
for i in {1..20}; do
    if warp-cli --accept-tos status &>/dev/null || warp-cli status &>/dev/null; then
        echo "[WARP] Daemon is ready"
        break
    fi
    sleep 1
done

# Register device with Cloudflare WARP (support both new and old warp-cli flags)
echo "[WARP] Registering device..."
REG_OUTPUT=$(warp-cli --accept-tos registration new 2>&1 || warp-cli registration new 2>&1 || true)
echo "[WARP] Registration output: $REG_OUTPUT"

# Configure proxy mode on port 4000
echo "[WARP] Enabling proxy mode on port 4000..."
MODE_OUTPUT=$(warp-cli --accept-tos mode proxy 2>&1 || warp-cli mode proxy 2>&1 || true)
echo "[WARP] Mode output: $MODE_OUTPUT"

PORT_OUTPUT=$(warp-cli --accept-tos proxy port 4000 2>&1 || warp-cli proxy port 4000 2>&1 || warp-cli --accept-tos set-proxy-port 4000 2>&1 || warp-cli set-proxy-port 4000 2>&1 || true)
echo "[WARP] Port output: $PORT_OUTPUT"

CONNECT_OUTPUT=$(warp-cli --accept-tos connect 2>&1 || warp-cli connect 2>&1 || true)
echo "[WARP] Connect output: $CONNECT_OUTPUT"

# Wait for connection status
echo "[WARP] Waiting for WARP connection..."
CONNECTED=false
for i in {1..30}; do
    STATUS=$(warp-cli --accept-tos status 2>&1 || warp-cli status 2>&1 || true)
    echo "[WARP] Status check $i: $STATUS"
    if echo "$STATUS" | grep -qi "connected"; then
        echo "[WARP] Connected to Cloudflare WARP!"
        CONNECTED=true
        break
    fi
    sleep 1
done

# Verify local proxy port 4000 is open and accepting socket connections
PROXY_READY=false
if python3 -c "import socket; s = socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 4000)); s.close()" 2>/dev/null; then
    PROXY_READY=true
    echo "[WARP] Proxy available and verified listening at 127.0.0.1:4000"
else
    # Give it a few extra seconds if WARP just connected
    echo "[WARP] Waiting for proxy port 4000 socket..."
    for i in {1..10}; do
        if python3 -c "import socket; s = socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 4000)); s.close()" 2>/dev/null; then
            PROXY_READY=true
            echo "[WARP] Proxy available and verified listening at 127.0.0.1:4000"
            break
        fi
        sleep 1
    done
fi

if [ "$PROXY_READY" = false ]; then
    echo "[WARP] WARNING: Local proxy port 4000 is not reachable."
    echo "[WARP] Unsetting proxy environment variables to allow direct network connections."
    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
fi

# Execute the main application command
echo "[WARP] Starting main application..."
exec "$@"

#!/bin/sh
# Seed custom agents and config into OPENFANG_HOME on first run
mkdir -p "$OPENFANG_HOME/agents"

for agent_dir in /opt/openfang/agents/*/; do
    agent_name=$(basename "$agent_dir")
    target="$OPENFANG_HOME/agents/$agent_name"
    if [ ! -d "$target" ]; then
        mkdir -p "$target"
        cp -r "$agent_dir"* "$target/"
    fi
done

if [ ! -f "$OPENFANG_HOME/config.toml" ] && [ -f /opt/openfang/config.toml ]; then
    cp /opt/openfang/config.toml "$OPENFANG_HOME/config.toml"
fi

# Start daemon in background
openfang start &
DAEMON_PID=$!

# Wait for API to be ready
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:4200/api/health > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Spawn br0br0 if not already running
if ! curl -sf http://127.0.0.1:4200/api/agents 2>/dev/null | grep -q '"name":"br0br0"'; then
    openfang agent spawn "$OPENFANG_HOME/agents/br0br0/agent.toml" 2>/dev/null && echo "br0br0 spawned" || echo "br0br0 spawn failed"
fi

wait $DAEMON_PID

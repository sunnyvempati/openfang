#!/bin/sh
# Seed custom agents and config into OPENFANG_HOME on first run
mkdir -p "$OPENFANG_HOME/agents"

for agent_dir in /opt/openfang/agents/*/; do
    agent_name=$(basename "$agent_dir")
    target="$OPENFANG_HOME/agents/$agent_name"
    mkdir -p "$target"
    cp -r "$agent_dir"* "$target/"
done

if [ -f /opt/openfang/config.toml ]; then
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

# Kill any stale br0br0 from previous boot, then spawn fresh from toml
STALE_ID=$(curl -sf http://127.0.0.1:4200/api/agents 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$STALE_ID" ]; then
    curl -sf -X DELETE "http://127.0.0.1:4200/api/agents/$STALE_ID" > /dev/null 2>&1
    sleep 1
fi
openfang agent spawn "$OPENFANG_HOME/agents/br0br0/agent.toml" 2>/dev/null && echo "br0br0 spawned" || echo "br0br0 spawn failed"

# Sync runtime quota and model (SQLite may cache old values)
BR0BR0_ID=$(curl -sf http://127.0.0.1:4200/api/agents 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$BR0BR0_ID" ]; then
    curl -sf -X PUT "http://127.0.0.1:4200/api/budget/agents/$BR0BR0_ID" \
        -H "Content-Type: application/json" \
        -d '{"max_llm_tokens_per_hour": 1000000, "max_cost_per_hour_usd": 100.0, "max_cost_per_day_usd": 1000.0, "max_cost_per_month_usd": 10000.0}' > /dev/null 2>&1 && echo "quota synced" || echo "quota sync failed"
    curl -sf -X PUT "http://127.0.0.1:4200/api/agents/$BR0BR0_ID/model" \
        -H "Content-Type: application/json" \
        -d '{"model": "claude-opus-4-6"}' > /dev/null 2>&1 && echo "model synced" || echo "model sync failed"
fi

# Copy MANUAL.md to br0br0 workspace so it survives context trims
mkdir -p /data/workspaces/br0br0
if [ -f "$OPENFANG_HOME/agents/br0br0/MANUAL.md" ]; then
    cp "$OPENFANG_HOME/agents/br0br0/MANUAL.md" /data/workspaces/br0br0/MANUAL.md
    echo "MANUAL.md deployed"
fi

wait $DAEMON_PID

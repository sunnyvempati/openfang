#!/bin/sh
mkdir -p "$OPENFANG_HOME/agents"

# Always overwrite agent files from image
for agent_dir in /opt/openfang/agents/*/; do
    agent_name=$(basename "$agent_dir")
    target="$OPENFANG_HOME/agents/$agent_name"
    mkdir -p "$target"
    cp -r "$agent_dir"* "$target/"
done

if [ -f /opt/openfang/config.toml ]; then
    cp /opt/openfang/config.toml "$OPENFANG_HOME/config.toml"
fi

# Copy MANUAL.md to br0br0 workspace
mkdir -p /data/workspaces/br0br0
if [ -f "$OPENFANG_HOME/agents/br0br0/MANUAL.md" ]; then
    cp "$OPENFANG_HOME/agents/br0br0/MANUAL.md" /data/workspaces/br0br0/MANUAL.md
    echo "MANUAL.md deployed"
fi

# Start daemon — if br0br0 exists in DB, reuses same ID; if not, spawns from toml
openfang start &
DAEMON_PID=$!

for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:4200/api/health > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Find br0br0 specifically (not assistant or other agents)
BR0BR0_ID=$(curl -sf http://127.0.0.1:4200/api/agents 2>/dev/null \
  | tr '{' '\n' | grep '"name":"br0br0"' | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

if [ -n "$BR0BR0_ID" ]; then
    curl -sf -X PUT "http://127.0.0.1:4200/api/budget/agents/$BR0BR0_ID" \
        -H "Content-Type: application/json" \
        -d '{"max_llm_tokens_per_hour": 0, "max_cost_per_hour_usd": 0, "max_cost_per_day_usd": 0, "max_cost_per_month_usd": 0}' \
        > /dev/null 2>&1 && echo "quota synced" || echo "quota sync failed"
    curl -sf -X PUT "http://127.0.0.1:4200/api/agents/$BR0BR0_ID/model" \
        -H "Content-Type: application/json" \
        -d '{"model": "claude-opus-4-6"}' \
        > /dev/null 2>&1 && echo "model synced" || echo "model sync failed"
fi

wait $DAEMON_PID

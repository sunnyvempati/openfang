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

# Spawn br0br0 if not already running
if ! curl -sf http://127.0.0.1:4200/api/agents 2>/dev/null | grep -q '"name":"br0br0"'; then
    openfang agent spawn "$OPENFANG_HOME/agents/br0br0/agent.toml" 2>/dev/null && echo "br0br0 spawned" || echo "br0br0 spawn failed"
fi

# Sync runtime quota (SQLite persists old values, toml changes need API push)
BR0BR0_ID=$(curl -sf http://127.0.0.1:4200/api/agents 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$BR0BR0_ID" ]; then
    curl -sf -X PUT "http://127.0.0.1:4200/api/budget/agents/$BR0BR0_ID" \
        -H "Content-Type: application/json" \
        -d '{"max_llm_tokens_per_hour": 500000}' > /dev/null 2>&1 && echo "quota synced" || echo "quota sync failed"
fi

wait $DAEMON_PID

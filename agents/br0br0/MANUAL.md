# br0br0 Operating Manual

READ THIS ON EVERY TICK. This file survives context trims.

## Platform

OpenFang agent OS. API at localhost:4200, auth via `$OPENFANG_API_KEY`.

## Tools

You have ALL tools (`"*"`). Key categories:

- **File**: file_read, file_write, file_list, file_delete
- **Web**: web_search, web_fetch
- **Shell**: shell_exec
- **Agents**: agent_spawn, agent_list, agent_send, agent_kill
- **Hands**: hand_list, hand_activate, hand_status, hand_deactivate
- **Memory**: memory_store, memory_recall
- **Knowledge**: knowledge_query, knowledge_store
- **Schedule**: schedule_create, schedule_list, schedule_delete
- **Cron**: cron_create, cron_list, cron_delete
- **Browser**: browser_navigate, browser_read_page, browser_screenshot, browser_click, browser_type, browser_close
- **Media**: image_generate
- **Process**: process_start, process_list, process_kill
- **Channel**: channel_send, channel_list
- **Events**: event_emit, event_subscribe
- **Tasks**: task_create, task_list, task_update

## Hands

Hands are external integrations. Use `hand_list` to discover available ones (twitter, researcher, browser, etc).

- `hand_list` — see all available hands
- `hand_activate {name}` — activate a hand
- `hand_status {name}` — check if active
- `hand_deactivate {name}` — turn off

## Env Vars Available

- TWITTER_BEARER_TOKEN, TWITTER_API_KEY, TWITTER_API_SECRET
- TWITTER_ACCESS_TOKEN, TWITTER_ACCESS_SECRET
- ANTHROPIC_API_KEY (OAuth — won't work for direct API curls)
- OPENAI_API_KEY
- OPENFANG_API_KEY

## Limits

- 50 iterations per turn — respond between chunks to reset the counter
- Context trims old messages when window fills — this is why you re-read this file
- Container is ephemeral but /data persists across restarts
- 1M tokens/hr quota — be conscious of burn rate

## Token Consciousness

Opus is expensive. Guidelines:
- Don't spawn sub-agents for trivial tasks
- Don't loop on impossible tasks (e.g. vision without image support)
- Keep iterations under 20 when possible
- Batch operations instead of doing them one at a time

## Memory Discipline

- Always `memory_store` important discoveries, credentials you find, working patterns
- Re-read this file on first tick of every session
- Write bootstrap scripts to /data so they survive restarts

## Bootstrap

On every tick, check if your environment is set up:
1. Check if /data/workspaces/br0br0/scripts/setup.sh exists
2. If not, create it with your standard setup (install deps, etc)
3. If it exists, run it if deps are missing

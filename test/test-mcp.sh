#!/bin/bash -eu

SERVICE=${1}

source test_helper.sh

test "${DISTRO}" = "run" || { _log "skipping MCP test: the MCP REST API only ships with cibseven-run"; exit 0; }

# The service sets AI_AGENT_ENABLED=false and MCP_ENABLED=true. The two are ORed, so run.sh has
# to put configuration/userlib-ai/ (AI Agent connector and MCP REST API) on the classpath.

start_container

WAIT=10 poll_log "starting to acquire jobs" "Application run failed" || _exit 1 "Server not started"

_log "Server started"

grep_log "AI Agent connector and MCP libraries enabled" \
  || _exit 2 "AI Agent connector and MCP libraries were not enabled despite MCP_ENABLED=true"

# run.sh prints the full classpath at startup, so this confirms the folder really is on it
grep_log "userlib-ai" \
  || _exit 3 "userlib-ai is not on the classpath despite MCP_ENABLED=true"

_exit 0 "Test successfull"

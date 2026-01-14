#!/bin/bash -eu

SERVICE=${1}

source test_helper.sh

start_container

WAIT=10 poll_log "starting to acquire jobs" "Application run failed" || _exit 1 "Server not started"

_log "Server started"

# Test OpenTelemetry metrics endpoint
_log "Testing OpenTelemetry metrics endpoint"
curl -s http://localhost:9464/metrics | grep -q "target_info" || _exit 8 "OpenTelemetry metrics not available"
_log "OpenTelemetry metrics available"

_exit 0 "Test successfull"

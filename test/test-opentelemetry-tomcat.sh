#!/bin/bash -eu

SERVICE=${1}

source test_helper.sh

start_container

poll_log "org.apache.catalina.startup.Catalina.start Server startup in" "^SEVERE" || _exit 1 "Server not started"

_log "Server started"

# Test OpenTelemetry metrics endpoint
_log "Testing OpenTelemetry metrics endpoint"
curl -s http://localhost:9464/metrics | grep -q "target_info" || _exit 3 "OpenTelemetry metrics not available"
_log "OpenTelemetry metrics available"

_exit 0 "Test successfull"
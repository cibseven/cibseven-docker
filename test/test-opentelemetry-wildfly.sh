#!/bin/bash -eu

SERVICE=${1}

source test_helper.sh

# Increase timeout for WildFly startup
# Can be overridden by setting JAVA_OPTS before running script
export JAVA_OPTS="${JAVA_OPTS:--Djboss.as.management.blocking.timeout=600 -Xms1024m -Xmx2048m -XX:MetaspaceSize=256M}"

_log "Using JAVA_OPTS: ${JAVA_OPTS}"

start_container

poll_log 'started in' 'started (with errors) in' || _exit 1 "Server not started"

_log "Server started"

# Test OpenTelemetry metrics endpoint
_log "Testing OpenTelemetry metrics endpoint"
curl -s http://localhost:9464/metrics | grep -q "target_info" || _exit 3 "OpenTelemetry metrics not available"
_log "OpenTelemetry metrics available"

_exit 0 "Test successfull"
#!/bin/bash -eu
RETRIES=100
WAIT=5

GHA=${GITHUB_ACTIONS:-false}
if [ "${GHA}" = "true" ]; then
  shopt -s expand_aliases
  alias docker-compose="docker compose"
fi

function _log {
  >&2 echo $@
}

function stop_container {
  docker logs $(container_id)
  docker-compose kill ${SERVICE}
  docker-compose rm --force ${SERVICE}
}

function _exit {
  stop_container
  _log $2
  exit $1
}

function start_container {
  docker-compose up -d --no-recreate ${SERVICE} || _exit 1 "Unable to start compose"
}

function container_id {
  docker-compose ps -q ${SERVICE}
}

function grep_log {
  (docker logs $(container_id) 2>&1 | grep -q "$1")
}

function poll_log {
  local good="$1"
  local bad="$2"

  for i in $(seq $RETRIES); do
    _log "Polling log for the $i. time"

    grep_log "$bad" && return 1
    grep_log "$good" && return 0

    if [ $i -eq $RETRIES ]; then
      return 1
    else
      _log "Waiting for $WAIT seconds"
      sleep $WAIT
    fi
  done
}

function create_user {
  rm -f dumped-headers.txt
  curl --dump-header dumped-headers.txt --fail -s -o/dev/null http://localhost:8080/camunda/app/admin/default/setup/
  curl -XPOST --cookie dumped-headers.txt -H "$(cat dumped-headers.txt | grep X-XSRF-TOKEN | tr -d '\r\n')" -H "Accept: application/json" -H "Content-Type: application/json" --fail -s --data '{"profile":{"id":"demo", "firstName":"Demo", "lastName":"Demo", "email":""}, "credentials":{"password":"demo"}}' -o/dev/null http://localhost:8080/camunda/api/admin/setup/default/user/create
}

function test_login {
  logger "Attempting login to http://localhost:8080/camunda/api/admin/auth/user/default/login/${1}"
  rm -f dumped-headers.txt
  curl --dump-header dumped-headers.txt --fail -s -o/dev/null http://127.0.0.1:8080/camunda/app/${1}/default/
  # dumped-headers.txt uses windows line endings, drop them
  curl --cookie dumped-headers.txt -H "$(cat dumped-headers.txt | grep X-XSRF-TOKEN | tr -d '\r\n')" -H "Accept: application/json" --fail -s --data 'username=demo&password=demo' -o/dev/null http://127.0.0.1:8080/camunda/api/admin/auth/user/default/login/${1}
}

function test_login_webapp {
  logger "Attempting login to http://localhost:8080/webapp/services/v1/auth/login"
  curl -H "Accept: application/json" \
       -H "Content-Type: application/json" \
       -H "Cookie: JSESSIONID=41AF408D540E7E17CF844B225123F729" \
       --fail -s -o/dev/null \
       --data '{"username":"demo","password":"demo","type":"org.cibseven.webapp.auth.rest.StandardLogin"}' \
       http://localhost:8080/webapp/services/v1/auth/login
}

function test_encoding {
  curl --fail -w "\n" http://localhost:8080/engine-rest/deployment/create -F deployment-name=testEncoding -F testEncoding.bpmn=@testEncoding.bpmn
  curl --fail -w "\n" -H "Content-Type: application/json" -d '{}'  http://localhost:8080/engine-rest/process-definition/key/testEncoding/start
}

# Expected Prometheus metric names from opentelemetry/jmx_config.yaml (prefix os. + mapping metrics, dots -> underscores).
EXPECTED_JMX_METRICS=(
  os_cpu_count
  os_cpu_time
  os_cpu_recent_utilization
  os_system_cpu_load_1m
  os_system_cpu_utilization
  os_file_descriptor_open_count
  os_file_descriptor_max_count
  os_virtual_memory_committed_size
  os_physical_memory_free_size
  os_physical_memory_total_size
  os_swap_space_free_size
  os_swap_space_total_size
)

# Verifies that all expected JMX metrics are present on the Prometheus metrics endpoint.
# Usage: assert_jmx_metrics [metrics_url]
# Default metrics_url: http://localhost:9464/metrics
function assert_jmx_metrics {
  local metrics_url="${1:-http://localhost:9464/metrics}"
  local metrics_output
  local missing=""

  metrics_output=$(curl -s --fail "$metrics_url") || { _log "Failed to fetch $metrics_url"; return 1; }

  for prometheus_name in "${EXPECTED_JMX_METRICS[@]}"; do
    if ! echo "$metrics_output" | grep -qE "(^|[[:space:]])${prometheus_name}([{\s]|$)"; then
      [ -n "$missing" ] && missing="$missing, "
      missing="${missing}${prometheus_name}"
    fi
  done

  if [ -n "$missing" ]; then
    _log "Missing expected JMX metrics: $missing"
    return 1
  fi
  return 0
}

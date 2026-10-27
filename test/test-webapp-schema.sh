#!/bin/bash -eu

SERVICE=${1}

source test_helper.sh

# The service sets WEBAPP_SCHEMA_ENABLED=false, which tells the engine to leave the webclient
# tables (MOD_, CHAT_, NOTIF_) out of the database. The configuration endpoint reports the schema
# version of those tables, so it has to come back null here - that is how the webclient knows the
# modeler, chat and notification features are unavailable.

start_container

case "${DISTRO}" in
  tomcat)       poll_log "org.apache.catalina.startup.Catalina.start Server startup in" "^SEVERE" ;;
  wildfly)      poll_log 'started in' 'started (with errors) in' ;;
  run|run4)     WAIT=10 poll_log "starting to acquire jobs" "Application run failed" ;;
  *)            _exit 1 "Unknown distro: ${DISTRO}" ;;
esac || _exit 1 "Server not started"

_log "Server started"

CONFIGURATION=$(curl --fail -s -H "Accept: application/json" http://localhost:8080/engine-rest/configuration) \
  || _exit 2 "Unable to read the configuration endpoint"

echo "${CONFIGURATION}" | grep -q '"webappSchemaVersion"' \
  || _exit 3 "Configuration endpoint does not report webappSchemaVersion"

echo "${CONFIGURATION}" | grep -q '"webappSchemaVersion"[[:space:]]*:[[:space:]]*null' \
  || _exit 4 "Webclient tables were created despite WEBAPP_SCHEMA_ENABLED=false: ${CONFIGURATION}"

_exit 0 "Test successfull"

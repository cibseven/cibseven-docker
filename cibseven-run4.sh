#!/bin/bash
set -Eeu

trap 'Error on line $LINENO' ERR

source $(dirname "$0")/wait_for_it-lib.sh

# Set Password as Docker Secrets for Swarm-Mode
if [[ -z "${DB_PASSWORD:-}" && -n "${DB_PASSWORD_FILE:-}" && -f "${DB_PASSWORD_FILE:-}" ]]; then
  export DB_PASSWORD="$(< "${DB_PASSWORD_FILE}")"
fi

# For compatibility: when DB_ variables are set, translate them to SPRING_ variables.
# Otherwise [defaults](https://github.com/cibseven/cibseven/blob/master/distro/run4/assembly/resources/default.yml)
# will be used.

if [[ -z "${SPRING_DATASOURCE_DRIVER_CLASS_NAME:-}" && -n "${DB_DRIVER:-}" ]]; then
  export SPRING_DATASOURCE_DRIVER_CLASS_NAME="${DB_DRIVER}"
fi

if [[ -z "${SPRING_DATASOURCE_PASSWORD:-}" && -n "${DB_PASSWORD:-}" ]]; then
  export SPRING_DATASOURCE_PASSWORD="${DB_PASSWORD}"
fi

if [[ -z "${SPRING_DATASOURCE_USERNAME:-}" && -n "${DB_USERNAME:-}" ]]; then
  export SPRING_DATASOURCE_USERNAME="${DB_USERNAME}"
fi

if [[ -z "${SPRING_DATASOURCE_URL:-}" && -n "${DB_URL:-}" ]]; then
  export SPRING_DATASOURCE_URL="${DB_URL}"
fi

if [ "${DEBUG}" = "true" ]; then
  echo "Enabling debug mode, JPDA accessible under port 8000"
  export JAVA_OPTS="${JAVA_OPTS} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:8000"
fi

# OpenTelemetry Agent configuration
# Load the agent via JAVA_OPTS instead of JAVA_TOOL_OPTIONS
export JAVA_OPTS="${JAVA_OPTS:-} -javaagent:/camunda/javaagent/opentelemetry-javaagent-${OPENTELEMETRY_AGENT_VERSION}.jar"

# Webclient schema toggle: webappSchemaEnabled in the yml decides whether the engine creates the
# modeler, chat and notification tables. Unset leaves the value the distribution ships; setting
# WEBAPP_SCHEMA_ENABLED overrides it with a system property, which keeps the case the
# generic-properties map key requires, and fails if there is nothing to override.
if [ -n "${WEBAPP_SCHEMA_ENABLED:-}" ]; then
  for CONFIG in /camunda/configuration/default.yml /camunda/configuration/production.yml; do
    if [ -f "${CONFIG}" ] && ! grep -q '^ *webappSchemaEnabled:' "${CONFIG}"; then
      echo "ERROR: can't find and update webappSchemaEnabled in the config file: ${CONFIG}" >&2
      exit 1
    fi
  done
  export JAVA_OPTS="${JAVA_OPTS:-} -Dcamunda.bpm.generic-properties.properties.webappSchemaEnabled=${WEBAPP_SCHEMA_ENABLED}"
fi

CMD="/camunda/internal/run.sh start"

wait_for_it

# shellcheck disable=SC2086
exec ${CMD} "$@"

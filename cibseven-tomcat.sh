#!/bin/bash
set -Eeu

trap 'Error on line $LINENO' ERR

source $(dirname "$0")/wait_for_it-lib.sh

# Use existing tomcat distribution if present..
CATALINA_HOME="${CATALINA_HOME:-/camunda}"

# Set default values for DB_ variables
# Set Password as Docker Secrets for Swarm-Mode
if [[ -z "${DB_PASSWORD:-}" && -n "${DB_PASSWORD_FILE:-}" && -f "${DB_PASSWORD_FILE:-}" ]]; then
  export DB_PASSWORD="$(< "${DB_PASSWORD_FILE}")"
fi

DB_DRIVER=${DB_DRIVER:-org.h2.Driver}
DB_PASSWORD=${DB_PASSWORD:-sa}
DB_URL=${DB_URL:-jdbc:h2:./camunda-h2-dbs/process-engine;TRACE_LEVEL_FILE=0;DB_CLOSE_ON_EXIT=FALSE}
DB_USERNAME=${DB_USERNAME:-sa}

XML_JDBC="//Resource[@name='jdbc/ProcessEngine']"
XML_DRIVER="${XML_JDBC}/@driverClassName"
XML_URL="${XML_JDBC}/@url"
XML_USERNAME="${XML_JDBC}/@username"
XML_PASSWORD="${XML_JDBC}/@password"
XML_MAXACTIVE="${XML_JDBC}/@maxActive"
XML_MINIDLE="${XML_JDBC}/@minIdle"
XML_MAXIDLE="${XML_JDBC}/@maxIdle"

if [ -z "$SKIP_DB_CONFIG" ]; then
  echo "Configure database"
  xmlstarlet ed -L \
    -u "${XML_DRIVER}" -v "${DB_DRIVER}" \
    -u "${XML_URL}" -v "${DB_URL}" \
    -u "${XML_USERNAME}" -v "${DB_USERNAME}" \
    -u "${XML_PASSWORD}" -v "${DB_PASSWORD}" \
    -u "${XML_MAXACTIVE}" -v "${DB_CONN_MAXACTIVE}" \
    -u "${XML_MINIDLE}" -v "${DB_CONN_MINIDLE}" \
    -u "${XML_MAXIDLE}" -v "${DB_CONN_MAXIDLE}" \
    -u "${XML_JDBC}/@testOnBorrow" -v "${DB_VALIDATE_ON_BORROW}" \
    -i "${XML_JDBC}[not(@testOnBorrow)]" -t attr -n "testOnBorrow" -v "${DB_VALIDATE_ON_BORROW}" \
    -u "${XML_JDBC}/@validationQuery" -v "${DB_VALIDATION_QUERY}" \
    -i "${XML_JDBC}[not(@validationQuery)]" -t attr -n "validationQuery" -v "${DB_VALIDATION_QUERY}" \
    "${CATALINA_HOME}/conf/server.xml"
fi

# OpenTelemetry Agent configuration
# Load the agent via CATALINA_OPTS (Tomcat-specific) instead of JAVA_TOOL_OPTIONS
export CATALINA_OPTS="${CATALINA_OPTS:-} -javaagent:/camunda/javaagent/opentelemetry-javaagent-${OPENTELEMETRY_AGENT_VERSION}.jar"

CMD="${CATALINA_HOME}/bin/catalina.sh"
if [ "${DEBUG}" = "true" ]; then
  echo "Enabling debug mode, JPDA accesible under port 8000"
  export JPDA_ADDRESS="0.0.0.0:8000"
  CMD+=" jpda"
fi


CMD+=" run"

wait_for_it

# Define the target file path
FILE="$CATALINA_HOME/lib/cibseven-webclient.properties"

# Check if the file already exists
if [ ! -f "$FILE" ]; then
  # Create directory if it doesn't exist
  # mkdir -p "$(dirname "$FILE")"

  # Generate a 155-character alphanumeric random string
  RANDOM_STRING=$(LC_CTYPE=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 155)

  # Write the content to the file
  echo "cibseven.webclient.authentication.jwtSecret=$RANDOM_STRING" > "$FILE"

  echo "File \"$FILE\" created with random jwtSecret."
else
  echo "File \"$FILE\" already exists. No changes made."
fi

# shellcheck disable=SC2086
exec ${CMD}

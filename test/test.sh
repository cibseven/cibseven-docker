#!/bin/bash -xeu

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

cd ${DIR}

# Java 21 is the default and keeps the unprefixed tag; other Java versions get a javaNN- prefix.
if [ "${JAVA:-21}" = "21" ]; then
    export IMAGE_TAG="${DISTRO}-${PLATFORM}"
else
    export IMAGE_TAG="java${JAVA}-${DISTRO}-${PLATFORM}"
fi

source test_helper.sh

docker-compose up --force-recreate -d postgres mysql opentelemetry-collector
./test-${DISTRO}.sh cibseven
./test-${DISTRO}.sh cibseven-mysql
./test-${DISTRO}.sh cibseven-postgres
./test-${DISTRO}.sh cibseven-password-file
./test-opentelemetry-${DISTRO}.sh cibseven-opentelemetry
./test-webclient-extensions.sh cibseven-modeler-disabled
./test-debug.sh cibseven-debug
docker-compose down -v
cd -

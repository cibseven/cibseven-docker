#!/bin/bash -xeu

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

cd ${DIR}

export IMAGE_TAG="${DISTRO}-${PLATFORM}"

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

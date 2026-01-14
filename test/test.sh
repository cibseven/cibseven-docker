#!/bin/bash -xeu

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

cd ${DIR}

source test_helper.sh

docker-compose up --force-recreate -d postgres mysql opentelemetry-collector
./test-${DISTRO}.sh camunda
./test-${DISTRO}.sh camunda-mysql
./test-${DISTRO}.sh camunda-postgres
./test-${DISTRO}.sh camunda-password-file
./test-opentelemetry-${DISTRO}.sh camunda-opentelemetry
./test-debug.sh camunda-debug
docker-compose down -v
cd -

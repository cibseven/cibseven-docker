#!/bin/bash -xeu

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

cd ${DIR}

# Set up the IMAGE_TAG based on JAVA version for proper image naming
if [ "${JAVA:-17}" = "21" ]; then
    export IMAGE_TAG="java21-${DISTRO}-${PLATFORM}"
else
    export IMAGE_TAG="${DISTRO}-${PLATFORM}"
fi

source test_helper.sh

docker-compose up --force-recreate -d postgres mysql
./test-${DISTRO}.sh camunda
./test-${DISTRO}.sh camunda-mysql
./test-${DISTRO}.sh camunda-postgres
./test-${DISTRO}.sh camunda-password-file
./test-prometheus-jmx-${DISTRO}.sh camunda-prometheus-jmx
./test-debug.sh camunda-debug
docker-compose down -v
cd -

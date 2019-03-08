#!/bin/bash

if [ $# -eq 0 ]; then
  tests_to_execute="test_all"
else
  tests_to_execute="test $@"
fi

test_command="mix $tests_to_execute"

echo "Will execute: $test_command"

docker-compose build && \
  docker-compose run \
    -e DATABASE_URL=postgres://postgres:postgres@postgres:5432/sanbase_test \
    -e TIMESCALE_DATABASE_URL=postgres://postgres:postgres@postgres:5432/sanbase_timescale_test \
    -e INFLUXDB_HOST=influxdb \
    -e MIX_ENV=test \
    sanbase sh -c "$test_command"

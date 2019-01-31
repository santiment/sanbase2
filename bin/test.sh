#!/bin/bash

docker-compose build && \
  docker-compose run \
    -e DATABASE_URL=postgres://postgres:postgres@postgres:5432/sanbase_test \
    -e TIMESCALE_DATABASE_URL=postgres://postgres:postgres@postgres:5432/sanbase_timescale_test \
    -e INFLUXDB_HOST=influxdb \
    -e MIX_ENV=test \
    sanbase sh -c "mix test_all"

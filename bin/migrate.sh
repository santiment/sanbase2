#!/bin/bash

echo "Resetting database in dev environment..."

docker-compose run \
  sanbase sh -c "mix do ecto.drop, ecto.create, ecto.load, ecto.migrate"

echo "Resetting database in test environment..."

docker-compose run \
  -e MIX_ENV=test \
  sanbase sh -c "mix do ecto.drop, ecto.create, ecto.load"

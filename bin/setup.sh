#!/bin/bash

docker-compose run sanbase sh -c "mix deps.get && mix ecto.setup_all && mix run priv/repo/seeds.exs && cd assets/; yarn install; cd ../app; yarn install"

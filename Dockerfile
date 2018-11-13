FROM node:8.12.0-alpine as react_builder

ARG GIT_HEAD
RUN GIT_HEAD=$GIT_HEAD

WORKDIR /app

COPY ./app/package.json /app/package.json
COPY ./app/yarn.lock /app/yarn.lock
RUN yarn

COPY ./app /app

RUN yarn build

# Elixir and phoenix assets build image
FROM elixir:1.7.4 as code_builder

ENV MIX_ENV prod

RUN apt-get update \
  && curl -sL https://deb.nodesource.com/setup_8.x | bash \
  && apt-get install -y nodejs git
RUN npm install -g yarn

RUN mix local.hex --force
RUN mix local.rebar --force

WORKDIR /app

COPY mix.lock /app/mix.lock
COPY mix.exs /app/mix.exs
RUN mix deps.get
RUN mix deps.compile

COPY ./assets/package.json /app/assets/package.json
COPY ./assets/yarn.lock /app/assets/yarn.lock

RUN cd assets && yarn

COPY . /app

ARG SECRET_KEY_BASE

RUN cd assets && yarn build
RUN SECRET_KEY_BASE=$SECRET_KEY_BASE mix compile
RUN mix phx.digest
RUN mix release

# Release image
FROM elixir:1.7.4

RUN apt-get install -y --only-upgrade bash

WORKDIR /app

COPY --from=code_builder /app/_build/prod/rel/sanbase .
COPY --from=react_builder /app/build /app/lib/sanbase-0.0.1/priv/static/

CMD bin/sanbase foreground

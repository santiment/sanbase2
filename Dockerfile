# Elixir and phoenix assets build image
FROM elixir:1.8.2-otp-22-alpine as code_builder

ENV MIX_ENV prod

RUN apk add --no-cache nodejs git make g++ nodejs-npm

RUN mix local.hex --force
RUN mix local.rebar --force

WORKDIR /app

COPY mix.lock /app/mix.lock
COPY mix.exs /app/mix.exs
RUN mix deps.get
RUN mix deps.compile

COPY ./assets /app/assets
RUN cd assets && npm install
RUN cd assets && npm run build:prod

# Copy all files only before compile so we can cache the deps fetching layer
COPY . /app
RUN mix format --check-formatted

RUN mix compile
RUN mix phx.digest
RUN mix release

# Release image
FROM elixir:1.8.2-otp-22-alpine

RUN apk add --no-cache bash

WORKDIR /app

COPY --from=code_builder /app/_build/prod/rel/sanbase .

ENV REPLACE_OS_VARS=true

CMD bin/sanbase foreground

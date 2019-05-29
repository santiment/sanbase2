# Elixir and phoenix assets build image
FROM elixir:1.8.2-otp-22 as code_builder

ENV MIX_ENV prod

RUN apt-get update \
  && curl -sL https://deb.nodesource.com/setup_8.x | bash \
  && apt-get install -y nodejs git

RUN mix local.hex --force
RUN mix local.rebar --force

WORKDIR /app

COPY mix.lock /app/mix.lock
COPY mix.exs /app/mix.exs
RUN mix deps.get
RUN mix deps.compile

COPY ./assets/package.json /app/assets/package.json
COPY ./assets/package-lock.json /app/assets/package-lock.json

RUN cd assets && npm install

COPY . /app

ARG SECRET_KEY_BASE

RUN cd assets && npm run build:prod
RUN SECRET_KEY_BASE=$SECRET_KEY_BASE mix compile
RUN mix phx.digest
RUN mix release

# Release image
FROM elixir:1.8.0

RUN apt-get install -y --only-upgrade bash

WORKDIR /app

COPY --from=code_builder /app/_build/prod/rel/sanbase .

ENV REPLACE_OS_VARS=true

CMD bin/sanbase foreground

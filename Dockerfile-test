FROM elixir:1.8.2-otp-22-alpine

RUN apk add --no-cache git postgresql-client make g++

ENV MIX_ENV test

RUN mix local.hex --force
RUN mix local.rebar --force

WORKDIR /app

COPY mix.lock /app/mix.lock
COPY mix.exs /app/mix.exs

RUN mix deps.get
RUN mix deps.compile

COPY . /app
RUN mix format --check-formatted

CMD mix test_all --trace

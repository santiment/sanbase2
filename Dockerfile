FROM erlang:23 AS code_builder

# elixir expects utf8.
ENV ELIXIR_VERSION="v1.10.3" \
  LANG=C.UTF-8

RUN set -xe \
  && ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz" \
  && ELIXIR_DOWNLOAD_SHA256="f3035fc5fdade35c3592a5fa7c8ee1aadb736f565c46b74b68ed7828b3ee1897" \
  && curl -fSL -o elixir-src.tar.gz $ELIXIR_DOWNLOAD_URL \
  && echo "$ELIXIR_DOWNLOAD_SHA256  elixir-src.tar.gz" | sha256sum -c - \
  && mkdir -p /usr/local/src/elixir \
  && tar -xzC /usr/local/src/elixir --strip-components=1 -f elixir-src.tar.gz \
  && rm elixir-src.tar.gz \
  && cd /usr/local/src/elixir \
  && make install clean

ENV MIX_ENV prod

RUN apk add --no-cache make \
  g++ \
  git \
  nodejs \
  nodejs-npm \
  openssl \
  wget

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
RUN mix distillery.release

# Release image
FROM elixir:1.10.0-alpine

ENV MIX_ENV prod

RUN apk add --no-cache bash \
  imagemagick

WORKDIR /app

COPY --from=code_builder /app/_build/prod/rel/sanbase .

ENV REPLACE_OS_VARS=true

CMD bin/sanbase foreground

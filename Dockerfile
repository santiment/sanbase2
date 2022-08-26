# Elixir and phoenix assets build image
FROM elixir:1.13.3-slim as code_builder

ENV MIX_ENV prod

RUN apt-get update -y && apt-get install -y curl

RUN curl https://sh.rustup.rs -sSf | \
	sh -s -- --default-toolchain stable -y

ENV RUSTFLAGS="-C target-feature=-crt-static"

ENV PATH=/root/.cargo/bin:$PATH


RUN apt-get install -y build-essential \
	make \
	g++ \
	git \
	nodejs \
	npm \
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
FROM elixir:1.13.3-slim

ENV MIX_ENV prod

RUN apt-get update -y && apt-get install -y bash imagemagick

WORKDIR /app

COPY --from=code_builder /app/_build/prod/rel/sanbase .

ENV REPLACE_OS_VARS=true

CMD bin/sanbase foreground

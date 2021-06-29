# Elixir and phoenix assets build image
FROM santimentjenkins/elixir:1.12 as code_builder

ENV MIX_ENV prod

RUN apk add --no-cache curl

RUN curl https://sh.rustup.rs -sSf | \
	sh -s -- --default-toolchain stable -y

ENV RUSTFLAGS="-C target-feature=-crt-static"

ENV PATH=/root/.cargo/bin:$PATH

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
FROM santimentjenkins/elixir:1.12

ENV MIX_ENV prod

RUN apk add --no-cache bash \
	imagemagick

WORKDIR /app

COPY --from=code_builder /app/_build/prod/rel/sanbase .

ENV REPLACE_OS_VARS=true

CMD bin/sanbase foreground

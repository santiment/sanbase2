ARG ELIXIR_VERSION=1.14.4
ARG OTP_VERSION=25.3
ARG DEBIAN_VERSION=bullseye-20230227-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"
# TODO: Start using concrete version of Rust
ARG RUST_VERSION=1.69.0 

FROM ${BUILDER_IMAGE} as builder

# install build dependencies
RUN apt-get update -y && apt-get install -y \
	build-essential \
	make \
	g++ \
	git \
	nodejs \
	npm \
	openssl \
	wget \
	ca-certificates \
	gcc \
	libc6-dev \
	curl \
	&& apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
RUN mkdir /app
WORKDIR /app

# Add rust
RUN curl https://sh.rustup.rs -sSf | \
	sh -s -- --default-toolchain stable -y

ENV RUSTFLAGS="-C target-feature=-crt-static"

ENV PATH=/root/.cargo/bin:$PATH

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs \
	 config/ueberauth_config.exs \
	 config/ex_admin_config.exs \
	 config/notifications_config.exs \
	 config/scheduler_config.exs \
	 config/scrapers_config.exs \
	 config/stripe_config.exs \
	 config/${MIX_ENV}.exs \
	 config/

RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets

# check that the code is formatted
# RUN mix format --check-formatted

# compile assets
RUN cd assets && npm install
RUN cd assets && npm run build:prod
RUN mix phx.digest

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales imagemagick git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"

# Necessary as k8s sets it to /root and this causes permission issues when
# storing the cookie file during booting
ENV HOME=/app

RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/sanbase ./

USER nobody

CMD ["/bin/bash", "-c", "/app/bin/migrate && /app/bin/server"]

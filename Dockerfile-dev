FROM elixir:1.8.2-otp-22

# Install debian packages
RUN apt-get update \
  && curl -sL https://deb.nodesource.com/setup_8.x | bash \
  && apt-get install --yes build-essential \
                           git \
                           inotify-tools \
                           postgresql-client-9.6\
                           nodejs

# Install Phoenix packages
RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix archive.install --force https://github.com/phoenixframework/archives/raw/master/phx_new.ez

RUN mix format --check-formatted

WORKDIR /app
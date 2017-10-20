# NextJS build image
FROM node:8.7.0-alpine as nextjs_builder

WORKDIR /app

COPY ./app/package.json /app/package.json
COPY ./app/yarn.lock /app/yarn.lock
RUN yarn

COPY ./app /app

RUN yarn build

# NextJS build image
FROM node:8.7.0-alpine as nextjs_modules

WORKDIR /app

COPY ./app/package.json /app/package.json
COPY ./app/yarn.lock /app/yarn.lock
RUN yarn install --prod

# Elixir and phoenix assets build image
FROM elixir:1.5.2-alpine as code_builder

ENV MIX_ENV prod

RUN apk add --update nodejs nodejs-npm bash curl git
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
FROM elixir:1.5.2-alpine

RUN apk add --update bash nodejs nodejs-npm

WORKDIR /app

COPY --from=nextjs_builder /app/.next /app/app/.next
COPY --from=nextjs_builder /app/static /app/app/static
COPY --from=nextjs_modules /app/node_modules /app/app/node_modules
COPY --from=nextjs_builder /app/package.json /app/app/package.json
COPY --from=code_builder /app/_build/prod/rel/sanbase .

CMD bin/sanbase foreground

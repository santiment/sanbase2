# Sanbase

This is the source of the sanbase project of [`https://santiment.net`](https://santiment.net).

## Setup

  In order to run the project locally you need:

  * Elixir & NodeJS: `brew install elixir nodejs`
  * Install dependencies with `mix deps.get`
  * Install JS dependencies for the static frontend with `cd assets && yarn && cd ..`
  * Install JS dependencies for the next.js frontend with `cd app && yarn && cd ..`
  * Update your Postgres setup in `config/dev.exs`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

This setup is going to start 2 processes:
  * A Phoenix server, which is routing the traffic and responding to API requests
  * A node server, which is doing the server side rendering

## Running with docker

If you have docker you can run the app simply by running:

```bash
$ docker-compose up
```

This is going to run the app on port 4000, so [`localhost:4000`](http://localhost:4000) should be accessible.

## Structure of the app

All the JS code is in `app/`. The API code is in `lib/` and follows the phoenix 1.3
directory structure. You can find more info on how the JS side works on [Learning Next.js](https://learnnextjs.com). You can read more about how to define the API
endpoints from the [Phoenix docs](https://hexdocs.pm/phoenix/overview.html) or from the excellent [Thoughtbot JSON API guide](https://robots.thoughtbot.com/building-a-phoenix-json-api)

## .editorconfig

We have .editorconfig file in our root.

Config properties:

- `charset = utf-8` - use utf-8 encoding,
- `indent_style = space` - indent with spaces,
- `indent_size = 4` - indent size 4,
- `trim_trailing_whitespace = true` - will trim any useless trailing whitespaces,
- `insert_final_newline = true` - add new line at the end of the file;

## Integration tests

It is possible to write high level integration tests for the JS app using the `Hound`
integration testing framework. See the integration test in `test/integration/home_test.exs`
for an example of that. It is possible to setup the DB and click around the app using
a headless chrome browser. In order to run the tests you need `chromedriver` installed.
You can install the driver with:

```bash
$ brew install chromedriver
```

you can run the default tests with

```bash
$ mix test
```

This mix task is going to automatically run the `chromedriver` and the node server,
which are needed to run the tests.

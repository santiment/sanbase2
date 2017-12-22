# Sanbase

This is the source of the sanbase project of [`https://santiment.net`](https://santiment.net).

## Setup

  In order to run the project locally you need:

  * Install PostgreSQL and InfluxDB. On OS X you can do that with `brew install postgresql influxdb`
  * Elixir & NodeJS. On OS X you can do that with `brew install elixir nodejs`
  * Install dependencies with `mix deps.get`
  * Install JS dependencies for the static frontend with `cd assets && yarn && cd ..`
  * Install JS dependencies for the next.js frontend with `cd app && yarn && cd ..`
  * Create a file `config/dev.secret.exs` and put your PostgreSQL setup there. Example:

```elixir
use Mix.Config

config :sanbase, Sanbase.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgresql",
  password: "",
  database: "sanbase_dev",
  hostname: "localhost",
  pool_size: 10
```

  * Setup your database and import the seeds with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
For tests run `npm run test:js` and follow cli instructions. To read more about
frontend app, open README file in the app folder.

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

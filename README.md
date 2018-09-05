# Sanbase

This is the source of the sanbase project of [`https://santiment.net`](https://santiment.net).

## Setup

  In order to run the project locally you need:

  * Install PostgreSQL and InfluxDB. On OS X you can do that with `brew install postgresql influxdb`
  * You may need to run the servers after installing: `brew services start postgresql && brew services start influxdb`
  * Elixir & NodeJS. On OS X you can do that with `brew install elixir nodejs`
  * Install dependencies with `mix deps.get`
  * Install JS dependencies for the static frontend with `yarn --cwd assets`
  * Install JS dependencies for the next.js frontend with `yarn --cwd app`
  * If you don't have a database, run `createdb sanbase_dev`
  * Create a copy of `.env.example`, name it `.env` and adjust your settings there.
  * To enable phoenix live reloading you should have inotify-tools. This package requires to be [manually installed](https://github.com/rvoicilas/inotify-tools/wiki) on Linux and requires no installation on Windows and Mac OS X.
  * Setup your database and import the seeds with `mix ecto.setup`. If you need to reseed the database use `mix ecto.reset`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser. For details how to run the frontend tests, check the section about running the frontend tests in this file.

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

## Running the backend tests

Make sure you have a test DB: `createdb sanbase_test`. This is needed by the tests to validate logic, which relies on the DB.

In order to run the backend tests you need to run `mix test`. The default DB config is in [`config/test.exs`](config/test.exs). If you need to change the default config you can create a file `.env.test` and specify the DB URL there like this:


```bash
DATABASE_URL=postgres://custom_username:custom_password@localhost:5432/sanbase_test
```

## Running the frontend tests

The frontend application is in the `app` folder. To run the tests you can do:

```
yarn --cwd app test:js
```

This is going to run the tests in watch mode, so when you change the JS files the tests will automatically run.

If you need to update snapshots, press `u` after running the `yarn test:js`.

We use JEST, enzyme and jest snapshots for testing.

We use **standard** for js lint and **stylelint** for css. Use these commands the run the linters:

```
yarn --cwd app test:lint:js
yarn --cwd app test:lint:css
```

----

We have Storybook for our UI components

```
yarn --cwd app storybook
```

Open http://localhost:9001

## Setting up Hydra Oauth2 server locally
[Setup Hydra locally] (docs/hydra-development-setup.md)
[Grafana generic oauth setup] (docs/setup-generic-oauth-grafana.md)

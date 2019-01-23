# Sanbase

This is the source of the sanbase project of [`https://santiment.net`](https://santiment.net).

## Running with docker

If you have docker you can run the app simply by running:

```bash
$ bin/server.sh
```

This is going to run the app on port 4000, so [`localhost:4000`](http://localhost:4000) should be accessible.

There will no data in the database, so run this command to fill some information in the database:

```bash
$ bin/setup.sh
```

If you want to access an IEX console attached to the running server, run:

```bash
$ bin/console.sh
```

## Structure of the app

The API code is in `lib/` and follows the phoenix 1.3
directory structure. You can read more about how to define the API
endpoints from the [Phoenix docs](https://hexdocs.pm/phoenix/overview.html).

## Running the backend tests

Make sure you have a test DB: `createdb sanbase_test`. This is needed by the tests to validate logic, which relies on the DB.

In order to run the backend tests you need to run `mix test`. The default DB config is in [`config/test.exs`](config/test.exs). If you need to change the default config you can create a file `.env.test` and specify the DB URL there like this:


```bash
DATABASE_URL=postgres://custom_username:custom_password@localhost:5432/sanbase_test
```

## Setting up Hydra Oauth2 server locally
[Setup Hydra locally] (docs/hydra-development-setup.md)
[Grafana generic oauth setup] (docs/setup-generic-oauth-grafana.md)

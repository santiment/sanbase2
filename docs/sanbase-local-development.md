# Sanbase Local Development Guide

> Note: If you are willing to contribute only once - either by fixing a typo or
> any other small change, you can always submit a PR and that will automatically
> run the tests in the CI.

In this document a detailed description on how to run the project locally is
found. Note that this project is not intended to be run by a wide range of
people and is not intended to be self-hosted.

The project is a data-centric application that, in the most parts, serves and
uses data from relational and timeseries databases. The data in the relational
databse is managed by the application and read/write access is required. The
data in the timeseries database (Clickhouse) is computed and inserted by other
services, managed by the bigdata and data science teams. The data in this
database is only read and never written.

## Prerequisites

The mandatory dependencies are:

- Postgres
- Clickhouse.

Because Postgres is managed by sanbase and Clickhouse is not, Postgres is often
run locally and for Clickhouse the stage cluster is used. This is done so the
running of migration and applying changes to Postgres is easier and faster. You
can always run postgres from the docker-compose as well - this works fine with a
few caveats. Often postgres is available and running on Linux/MacOS and if you
opt to run it from docker-compose you either have to completely stop the local
Postgres or use a port other than 5432. When the current task does not involving
writing to the database or changing its schema, the stage cluster Postgres can
be used instead. This has the benefit of having a lot of users, insights,
projects and so on, so changes in APIs that serve data can be tested better.

In order to run the tests only Postgres is required - all calls to the other
databses and services are mocked.

## Running postgres locally

Depending on the OS you are using. Here are some guides that you can follow:

- [MacOS](https://dataschool.com/learn-sql/how-to-start-a-postgresql-server-on-mac-os-x/)
- [Linux](http://postgresguide.com/setup/install.html)

After a successful install of postgres, the credentials for a superuser must be
provided. By default the dev and test configurations use username `postgres` and
password `postgres`, so it is highly suggested to use them in order to avoid
local config changes.

How to create a super user with a given name and password is described [in this
guide](https://tableplus.com/blog/2018/10/how-to-create-superuser-in-postgresql.html#:~:text=For%20the%20PostgreSQL%20verions%208.1,SUPERUSER%20WITH%20PASSWORD%20'passwordstring'%3B
)

If you wish to use different username/password, you can provide them either in
the config files (dev.exs/dev.secret.exs, test.exs/test.secret.exs) or via an ENV
var (in the .env.dev/.env.test file)

After the credentials are properly set, it's time to setup the databse by executing:

```console
# mix ecto.setup
```

This will drop the existing `sanbase_dev`/`sanbase_test` database, create a new
empty one and load the schema as defined in `priv/repo/structure.sql`. This file
holds the up to date schema of the database. All database changes must be
applied as a migration. Before comiting the code to the remote repository, the
migration must be run locally with `mix ecto.migrate`. The final part of running
the migration is to update the `structure.sql` file.

As a last step before starting, the `seeds` can be (optionally) run. All seeds
are located in the `priv/repo` directory. They can be run as follows:

```console
# mix run priv/repo/seed_plans_and_products.exs
# mix run priv/repo/seeds.exs
```

> After running the `seed_plans_and_products.exs` seed, an optional sync with stripe can be done by providing the stripe credentials in the config file and executing:

> ```elixir
> Sanbase.Billing.sync_products_with_stripe()
> ```
> ---

When this step is done, now you can connect to the staging Clickhouse

## Connecting to stage services (Clickhouse, etc.)

If you are reading this then most probably you have followed the [Getting Started Guide](https://github.com/santiment/devops/wiki/Getting-Started
) and specifically the VPN part. All you need to do in order to connect to the stage clickhouse is connect to the stage VPN and add the following line to the `.env.dev` file:

```bash
CLICKHOUSE_DATABASE_URL="ecto://sanbase@clickhouse.stage.san:30901/default"
```

All the ENV vars for connecting to the stage/prod services with VPN can be found in the `.env.example` file. When some env var is needed, it can be copied from the `.env.example` to the `.env.dev` file and remove the comment (`#`) in order to enable it.

When this step is also done, the application can be run.

## Running sanbase locally

To run sanbase locally and attach an iex shell to it run:

```console
# iex --erl "-kernel shell_history enabled" -S mix phx.server
```

Let's break down the command:
- `mix phx.server`
- `iex -S mix phx.server` - star the phoenix server (`mix phx.server`) and attach an iex shell to it so commands can be executed (`iex -S <mix script>`)
- the `--erl "-kernel shell_history enabled"` is a not mandatory but very useful erlang flag. This way the commands you execute are stored and when the project is started again, the commands executed can be browser the same way as the shell history works.

This command is tedious to be written by hand everytime, so it is highly suggested to have proper aliases in your `~/.bashrc`/`~/.zshrc`/etc. file.

Here are some useful Elixir aliases for faster typing:

```bash
alias ecto-migrate='mix ecto.migrate && MIX_ENV=test mix ecto.migrate'
alias ecto-rollback='mix ecto.rollback && MIX_ENV=test mix ecto.rollback'
alias iex='iex --erl "-kernel shell_history enabled~"'
alias im='iex --erl "-kernel shell_history enabled" -S mix'
alias imps='iex --erl "-kernel shell_history enabled" -S mix phx.server'
alias iex='iex --erl "-kernel shell_history enabled"'
alias mc='mix compile'
alias mt='mix test'
alias mtf='mix test --failed'
alias mf='mix format'
alias mdg='mix deps.get'
alias mdc='mix deps.compile'
```

- `ecto-migrate`/`ecto-rollback` - When migrations are run it is important to run apply them both
to the dev and test databases. This make this easier.
- `iex` - Same as plain `iex` but with history enabled.
- `im` - same as `iex -S mix` but with history enabled.
- `imps` - same as `iex -S mix phx.server` but with history enabled.
- The rest are just shortcuts for the most commonly used mix commands

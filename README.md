# sanbase2

## What is this?

This is the source code for the GraphQL API server https://api.santiment.net/graphiql

The project structure can be found [here](docs/project-structure.md).

Guide for adding metrics can be found [here](docs/adding-metrics-guide.md)

Some tips to find issues while developing can be found [here](docs/development-tips.md)

## Dependencies

- Elixir 1.10
- Erlang/OTP 22

> Note: Erlang/OTP 23 and 24 remove some APIs and modules that are used in some
> core dependencies. As part of our work we submit PRs to these libraries to improve
> the integration with the latest Erlang versions. When possible, we'll migrate to these
> newer versions.

## Why Open Source?

- We like open source and all of the dependencies used in this project are open source, too.
- There are not that many production open source Elixir projects out there. If this repository can help someone with pieces of code, insipration or ideas, we will be happy.
- Santiment is a data-oriented company. This project cannot be run in isolation without the timeseries and relational databases with data. Open sourcing strikes a balance between helping the Elixir community and not revealing all of Santiment's secrets.

## Where is this used?

The API server powers a set of services:

- Sanbase - https://app.santiment.net
  - The website is the easiest way to consume the API as it does not require
    development skills. It is also the only place where many of the features are
    exposed, mainly those that require some UI to be usable:
    - Insights
    - Alerts
    - Watchlists
    - Screeners
    - User data
    - Trending words
    - Chart layouts
    - etc.
- Sanapi - https://neuro.santiment.net
  - Sanapi gives access to the raw GraphQL API and is aimed to users who have
    development skills.
- Sansheets - https://sheets.santiment.net
  - Sansheets is a Google Spreadsheet plugin that gives access to the data in
    the form of a spreadsheet by defining functions that can be invoked to fetch
    the data.
- Sanpy - https://github.com/santiment/sanpy
  - Sanpy is a python wrapper around the GraphQL API that makes it possible to
    fetch metrics in a few lines of code.

## Internal structure

Internally, sanbase2 is broken into 3 bigger parts:

- Scrapers - Fetch data from a few different sources - scraping prices or
  scraping some social data.
- Alerts - Use and monitor the timeseries data to trigger alerts when some
  precondition is met (price increases by more than 10%, a given ETH wallet
  spends coins, etc.)
- GraphQL API - Expose all available data through a GraphQL endpoint. This data
  includes:
  - The scraped data
  - The data computed by other services
  - Managing alerts
  - User data and authentication
  - Rate limiting per subscription plan
  - Projects data
  - Insights, voting and comments data
  - etc.

Elixir is a functional language with a very unique way of structuring applications.

## Running the project

The project has 3 Dockerfiles:

- `Dockerfile` - The production image is built using it
- `Dockerfile-dev` - Used in development environment
- `Dockerfile-test` - Used in test environment

There is also a `Jenkinsfile` which describes how to run the project in Jenkins
using the `Dockerfile-test` to run tests and, if they succeed and the branch is
`master`, `Dockerfile` to build the image that will be used in production

For local development the project can be run either inside Docker or
natively. If you're going to work on the project regularly, running natively
is preferred due to the speed of development.

In order to be able to start, the following dependencies are required:

### Required

- Postgres
- Clickhouse

### Optional

- Metricshub
- Tech Indicators
- InfluxDB
- Elasticsearch
- Parity

### Running outside Docker

This is the preferred way to run the project if you are going to work on the
project regularly because this way the development process and build times are
much faster.

[Running sanbase locallylocally](docs/sanbase-local-development.md)

## Running inside Docker

If you have docker you can run the app simply by running:

```bash
bin/server.sh
```

This is going to run the app on port 4000, so [`localhost:4000`](http://localhost:4000) should be accessible.

There will be no data in the database, so run this command to fill some information in the database:

```bash
bin/setup.sh
```

If you want to access an IEX console attached to the running server, run:

```bash
bin/console.sh
```

## Seeding data

To seed example data run:

```console
CLICKHOUSE_REPO_ENABLED=false mix run lib/mix/seeds/seeds.exs
```

## Structure of the app

The API code is in `lib/` and follows the phoenix 1.3
directory structure. You can read more about how to define the API
endpoints from the [Phoenix docs](https://hexdocs.pm/phoenix/overview.html).

## Running the backend tests

You can easily run the tests using docker with the command:

```bash
./bin/test.sh
```

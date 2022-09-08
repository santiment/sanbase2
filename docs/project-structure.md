# Project Structure

## Overview

Elixir is a functional language with a unique way to structure applications. The
application has a root supervisor tree which starts and monitors all of the
services <sup>[1](#service-definition)</sup> - databas repo, web endpoint,
caches, scrapers, rate limiters, etc. This resembles both microservice
architecture and a kubernetes cluster where, if any of the applications dies,
there is someone who will detect this and restart the application.

This way of thinking greatly inspires the way sanbase is written and extended.
Because Elixir is a functional language, the only way to structure code is with
functions that can be grouped in modules. There is no inheritence or any other
complex design pattern.

Every service <sup>[1](#service-definition)</sup> is contained in a directory
that has the same name. This means that the structure of the application is mostly
flat. Adding a new service is done by adding a new directory and developing the
service in it independently. It still will use the other modules and services
defined but only through their context modules and public interfaces.

## Important dependencies

- `OTP` - The set of libraries provided with Erlang. It includes GenServer, ETS,
  Supervisor, Application, etc. It is the main building block of all Elixir
  applications. Note that OTP can be used transparently and indirectlyl. For
  example in Phoenix every request is processed in a separate process, making
  the request processing highly concurrent. The programmer never spawns or sees
  any processes - everything is handled behind the scenes.
  Books to learn more about OTP:

  - Elixir in Action
  - Learn you some Erlang for great good
  - Elixir/Erlang documentation

- `Phoenix` - The Web phramework used to expose an web endpoint and spawn a new
  Books to learn more about Phoenix:

  - Programming Phoenix >= 1.4
    process per request.

- `Ecto` - The library used to communicate with databses. It provides DB
  connection, DB connection pools, DSL for not writing raw SQL, migrations,
  schema definitions, etc.
  Books to learn more about Ecto:

  - Programming Ecto

- `Absinthe` - The GraphQL server. It provides the whole GraphQL server
  capabilities - everything from parsing and processing the GraphQL request to
  buildng and sending the response.
  Books to learn Absinthe:

  - Craft GraphQL APIs in Elixir with Absinthe

- `Dataloader` - Used in combination with Absinthe to solve the N+1 problem.
  Provides a nice way to combine fetcihng data from the DB for multiple entries
  with a single query.

- In total around ~80 libraries are used.

## Structure Overview

The application provides 3 modes to start in - `web`, `signals` and `scrapers`.
Additionally, for local development and tests the application can be started in
`all` mode that starts all services.

A `mode` just defines what services should be started as part of the supervision
tree. To control which mode to start the application in, provide the
`CONTAINER_TYPE` env var with value `web`, `signals`, `scrapers` or `all`.

In the cluster there are 3 types of pods running - `sanbase-web`,
`sanbase-signals`, `sanbase-scrapers` - each one of them is powered by one of
the 3 modes.

There are 4 important files you can look at:

- `lib/sanbase/application.ex` - The top level supervisor. It defines the common
  services and init procedures for all modes.
- `lib/sanbase/web.ex` - A module defining two functions - `children/0` and
  `init/0`. These functions are invoked from `application.ex` when the mode is
  `web` to define a few additional children to be added to the supervisor and
  init procedures to be invoked.
- `lib/sanbase/scrapers.ex` - A module defining two functions - `children/0` and
  `init/0`. These functions are invoked from `application.ex` when the mode is
  `scrapers` to define a few additional children to be added to the supervisor
  and init procedures to be invoked.
- `lib/sanbase/scrapers.ex` - A module defining two functions - `children/0` and
  `init/0`. These functions are invoked from `application.ex` when the mode is
  `scrapers` to define a few additional children to be added to the supervisor
  and init procedures to be invoked.

### Scrapers

In this mode only the scrapers collecting data are started. This
includes price scraping from Coinmarketcap, some blockchain data scrapers and
a social data scraper. With time these scrapers will be moved out of sanbase.

### Alerts

Based on metric data (timeseries or blockchain data) many alerts can
be defined. Examples for such alerts are:

- Notify me when price of BTC goes up by more than 25%
- Notify me when the work `Bitcoin` is in the trending word
- Notify me when the address `0x123` spends more than 100 ETH.

The alerts code is located in the `lib/sanbase/alerts` directory.
Alerts are created and managed via the GraphQL API but when an alert
is fired, it sends the result via one or more of the following channels:

- Email
- Telegram
- Webhook

Along with the notification sent, the event is stored in Postgres and these
events can be retrieved via API.

### Web

This is the biggest and most complicated of all modes. This mode powers the [API
endpoint](https://api.santiment.net/graphiql). It is used for serving all the
data available and managing all resources.

There are a few different main types of data that can be retrieved and managed:

### Admin panel

Expose an admin panel to the database so data can be manipulated and added manually.

### Serving and managing user data

- Login/logout - Google/Twitter OAuth, Email token auth, Metamask
- Update user account
- Generate apikeys
- Stripe integration - payments

### Project Data

- The `project` is the main entity for which we define data. A project is an
  abstraction that sits on top of a tradable asset, most often connected with
  a blockchain contract/coin and a company. For example there are projects
  `Bitcoin` and `Ethereum` which are blockchains and tradable coins, but there
  is no single company behind them. There is also `Santiment` project which
  represents the santiment ERC20 token and the Santiment company.
  We serve the following data (and not only):
- Project name, ticker, slug
- Social data information - twitter/medium/telegram/discord/slack/email link
- How they spend the funds raised during the ICO (ETH spent over time metric)
- Development activity data from public Github Repo
- Hundreds of different metrics built on top of price and blockchain data.

### Metrics

Description of some of the metrics can be found on the [Academy Page](https://academy.santiment.net/metrics/)

Most of the metrics are tied to a project (all metrics that accept `slug` as
argument)

The metrics can divided into a few different categories:

- Timeseries metrics - List of `{datetime, value}` pairs.
- Histogram metrics - Non-timeseries metrics. This includes a wide range of
  possibilities - `{blockchain_label, value}`, `{address, owner, value}`, etc.
  pairs
- Aggregated data - Aggregate many data points into a single value. Example: The
  average price for the last 7 days is represented as a single float value.

### Caching

Fetching metrics is very resource consuming. In some cases it requires scanning
tens of gigabytes of data and aggregate it into a small list of data points. In
order to off-load the databases, a custom in-house caching solution is developed
that is suited to caching graphql timeseries requests.

### Insights

Medium-like post/comments system

### Comments

Provide comments for multiple different entities:

- Insights
- Blockchain Addresses
- Short URLs
- Timeline Events

## Glossary

### Service Definition

In the context of Elixir, a service is a module or a group of modules that can
be independently started (in a new process) under a supervisor. Examples for
such services are:

- Cache - A process that owns an ETS table, spawns a few other processes and
  manages exposes a cachinng interface (get/store with TTL)
- Scraper - A process that regularly asks a 3rd party service for data and
  stores the progress in a database. The progress storage is important so the
  work can be resumed from the proper place after restart/crash.
- Database Repo - [Ecto Repo](https://hexdocs.pm/ecto/Ecto.Repo.html) that
  manages that alone knows how to communicate with a database and manages the
  whole communciation with it. It manages a pool of connections and chooses (or
  spawns a new) a connection to handle every DB request.
- Web Endpoint - For every HTTP request spawn a new process and let it handle
  the whole HTTP request.
- Many more...

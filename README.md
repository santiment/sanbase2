# Next.js app with server side rendering and Phoenix API

This is a skeleton of a [Phoenix](http://phoenixframework.org) application, which uses
[Next.js](https://zeit.co/blog/next3) for rendering the frontend and phoenix for
implementing the API. The app uses server side rendering out of the box and can be
deployed on heroku with several very simple steps.

## Creating a new project

To create a new project, run the following command:

```bash
bash <(curl https://raw.githubusercontent.com/valo/phoenix_with_nextjs/add_install_script/install.sh) <PROJECT_NAME>
```

Replace `<PROJECT_NAME>` with the name of your project. The script will create a folder with the same name for your project.

To start the app:

  * Go in the folder of the app `cd <PROJECT_NAME>`
  * Install dependencies with `mix deps.get`
  * Install JS dependencies with `cd app && yarn && cd ..`
  * Update your Postgres setup in `config/dev.exs`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:3000`](http://localhost:3000) from your browser. Keep in
mind that this is the address on which the node.js server is running. Using this URL
ensures that the hot module reloading will work properly.

This setup is going to start 2 processes:
  * A Phoenix server, which is routing the traffic and responding to API requests
  * A node server, which is doing the server side rendering

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

## Deploying on Heroku

You can deploy the app very easily to heroku following these steps:

1. Clone the app with `git clone https://github.com/valo/phoenix_with_nextjs.git`
2. Go into the `phoenix_with_nextjs` folder `cd phoenix_with_nextjs`
3. Make sure you have installed and configured the [heroku cli](https://devcenter.heroku.com/articles/heroku-cli)
4. Create a heroku app with the needed buildpacks and a Postgres addon:

```bash
heroku create --buildpack "https://github.com/HashNuke/heroku-buildpack-elixir.git" --addons heroku-postgresql
heroku buildpacks:add https://github.com/gjaldon/heroku-buildpack-phoenix-static.git
```
5. Take a note of the URL of the new app and set the URL in the `WEBSITE_URL` variable

```bash
heroku config:add WEBSITE_URL=<url_of_the_new_app>
```

6. Deploy the app with `git push heroku`

If you want to be really efficient and have gzip compression and HTTP/2, use a CDN service
like [cloudflare](https://www.cloudflare.com) in front of your app.

## Why?

This application template includes the following features out of the box without the need of any configuration:

* Phoenix API for defining business logic and exposing data
* NextJS for writing the frontend using React-based components and routing
* Server side rendering (SSR) of the frontend app out of the box
* Integration testing framework, which allows to test the frontend app using headless chrome
* Very easy deployment to Heroku and to any other hosting service, including features likes SSR

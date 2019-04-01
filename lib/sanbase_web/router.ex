defmodule SanbaseWeb.Router do
  use SanbaseWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :basic_auth do
    plug(BasicAuth, use_config: {:ex_admin, :basic_auth})
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(RemoteIp)
    plug(SanbaseWeb.Graphql.ContextPlug)
  end

  pipeline :telegram do
    plug(SanbaseWeb.Plug.TelegramMatchPlug)
  end

  use ExAdmin.Router

  scope "/admin", ExAdmin do
    pipe_through([:browser, :basic_auth])
    admin_routes()
  end

  scope "/" do
    pipe_through(:api)

    forward(
      "/graphql",
      Absinthe.Plug,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      analyze_complexity: true,
      max_complexity: 10000,
      log_level: :info,
      before_send: {SanbaseWeb.Graphql.Absinthe, :before_send}
    )

    forward(
      "/graphiql",
      Absinthe.Plug.GraphiQL,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      document_providers: [
        SanbaseWeb.Graphql.DocumentProvider,
        Absinthe.Plug.DocumentProvider.Default
      ],
      analyze_complexity: true,
      max_complexity: 10000,
      # interface: :simple,
      before_send: {SanbaseWeb.Graphql.Absinthe, :before_send}
    )
  end

  scope "/", SanbaseWeb do
    pipe_through([:telegram])

    post(
      "/telegram/:path",
      TelegramController,
      :index
    )
  end

  scope "/", SanbaseWeb do
    pipe_through(:browser)

    get("/consent", RootController, :consent)
    get("/apiexamples", ApiExamplesController, :api_examples)
  end

  get("/env.js", SanbaseWeb.RootController, :react_env)

  if Mix.env() == :dev do
    pipeline :nextjs do
      plug(:accepts, ["html"])
      plug(:put_secure_browser_headers)
    end

    scope "/" do
      get("/*path", ReverseProxy, upstream: ["http://localhost:3000"])
    end
  else
    get("/", SanbaseWeb.RootController, :healthcheck)
  end
end

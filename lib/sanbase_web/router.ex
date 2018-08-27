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
    plug(SanbaseWeb.Graphql.PlugAttack)
    plug(SanbaseWeb.Graphql.ContextPlug)
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
      schema: SanbaseWeb.Graphql.Schema,
      analyze_complexity: true,
      max_complexity: 5000,
      log_level: :info
    )

    forward(
      "/graphiql",
      Absinthe.Plug.GraphiQL,
      schema: SanbaseWeb.Graphql.Schema,
      analyze_complexity: true,
      max_complexity: 5000,
      interface: :simple
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
    scope "/", SanbaseWeb do
      get("/*path", RootController, :index)
    end
  end
end

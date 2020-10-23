defmodule SanbaseWeb.Router do
  use SanbaseWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :basic_auth do
    plug(SanbaseWeb.Plug.BasicAuth)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(RemoteIp)
    plug(:fetch_session)
    plug(SanbaseWeb.Graphql.ContextPlug)
  end

  pipeline :telegram do
    plug(SanbaseWeb.Plug.TelegramMatchPlug)
  end

  pipeline :bot_login do
    plug(:fetch_session)
    plug(SanbaseWeb.Plug.BotLoginPlug)
  end

  use ExAdmin.Router

  scope "/admin", ExAdmin do
    pipe_through([:browser, :basic_auth])
    admin_routes()
  end

  scope "/admin2", SanbaseWeb do
    pipe_through([:browser, :basic_auth])
    import Phoenix.LiveDashboard.Router

    live_dashboard("/dashboard", metrics: SanbaseWeb.Telemetry)

    get("/anonymize_comment/:id", CommentModerationController, :anonymize_comment)
    get("/delete_subcomment_tree/:id", CommentModerationController, :delete_subcomment_tree)
    resources("/reports", ReportController)
  end

  scope "/" do
    pipe_through(:api)

    forward(
      "/graphql",
      Absinthe.Plug,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      document_providers: [
        SanbaseWeb.Graphql.DocumentProvider,
        Absinthe.Plug.DocumentProvider.Default
      ],
      analyze_complexity: true,
      max_complexity: 20_000,
      log_level: :info,
      before_send: {SanbaseWeb.Graphql.AbsintheBeforeSend, :before_send}
    )

    forward(
      "/graphiql",
      Absinthe.Plug.GraphiQL,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      socket: SanbaseWeb.UserSocket,
      document_providers: [
        SanbaseWeb.Graphql.DocumentProvider,
        Absinthe.Plug.DocumentProvider.Default
      ],
      analyze_complexity: true,
      max_complexity: 20_000,
      interface: :simple,
      log_level: :info,
      before_send: {SanbaseWeb.Graphql.AbsintheBeforeSend, :before_send}
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

  scope "/bot", SanbaseWeb do
    pipe_through([:bot_login])

    get(
      "/login/:path",
      BotLoginController,
      :index
    )

    get(
      "/login/:path/:user",
      BotLoginController,
      :index
    )
  end

  scope "/", SanbaseWeb do
    get("/projects_data", ProjectDataController, :data)
    post("/stripe_webhook", StripeController, :webhook)
  end

  scope "/", SanbaseWeb do
    pipe_through(:browser)

    get("/consent", RootController, :consent)
  end

  get("/", SanbaseWeb.RootController, :healthcheck)
end

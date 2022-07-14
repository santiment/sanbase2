defmodule SanbaseWeb.Router do
  use SanbaseWeb, :router

  pipeline :admin_pod_only do
    plug(SanbaseWeb.Plug.AdminPodOnly)
  end

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
    plug(SanbaseWeb.Graphql.AuthPlug)
    plug(SanbaseWeb.Graphql.ContextPlug)
    plug(SanbaseWeb.Graphql.RequestHaltPlug)
  end

  pipeline :telegram do
    plug(SanbaseWeb.Plug.TelegramMatchPlug)
  end

  pipeline :bot_login do
    plug(:fetch_session)
    plug(SanbaseWeb.Plug.BotLoginPlug)
  end

  use ExAdmin.Router
  use Kaffy.Routes, scope: "/admin3", pipe_through: [:admin_pod_only, :basic_auth]

  scope "/auth", SanbaseWeb do
    pipe_through(:browser)

    get("/delete", AccountsController, :delete)
    get("/:provider", AccountsController, :request)
    get("/:provider/callback", AccountsController, :callback)
  end

  scope "/admin", ExAdmin do
    pipe_through([:admin_pod_only, :browser, :basic_auth])
    admin_routes()
  end

  scope "/admin2", SanbaseWeb do
    pipe_through([:admin_pod_only, :browser, :basic_auth])
    import Phoenix.LiveDashboard.Router

    live_dashboard("/dashboard", metrics: SanbaseWeb.Telemetry, ecto_repos: [Sanbase.Repo])

    get("/anonymize_comment/:id", CommentModerationController, :anonymize_comment)
    get("/delete_subcomment_tree/:id", CommentModerationController, :delete_subcomment_tree)
    resources("/reports", ReportController)
    resources("/sheets_templates", SheetsTemplateController)
    resources("/webinars", WebinarController)
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
      max_complexity: 50_000,
      log_level: :info,
      before_send: {SanbaseWeb.Graphql.AbsintheBeforeSend, :before_send}
    )

    forward(
      "/graphiql",
      # Use own version of the plug with fixed XSS vulnerability
      SanbaseWeb.Graphql.GraphiqlPlug,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      socket: SanbaseWeb.UserSocket,
      document_providers: [
        SanbaseWeb.Graphql.DocumentProvider,
        Absinthe.Plug.DocumentProvider.Default
      ],
      analyze_complexity: true,
      max_complexity: 50_000,
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
    get("/api_metric_name_mapping", MetricNameController, :api_metric_name_mapping)
    get("/projects_data", ProjectDataController, :data)
    get("/cryptocompare_asset_mapping", CryptocompareAssetMappingController, :data)
    post("/stripe_webhook", StripeController, :webhook)
  end

  scope "/", SanbaseWeb do
    pipe_through(:api)

    get("/get_routed_conn", RootController, :get_routed_conn)
  end

  get("/", SanbaseWeb.RootController, :healthcheck)
  get("/healthcheck", SanbaseWeb.RootController, :healthcheck)
end

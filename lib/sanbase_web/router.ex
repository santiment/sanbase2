defmodule SanbaseWeb.Router do
  use SanbaseWeb, :router
  require Logger

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
    plug(:log_headers_plug)
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

  scope "/auth", SanbaseWeb do
    pipe_through(:browser)

    get("/delete", AccountsController, :delete)
    get("/:provider", AccountsController, :request)
    get("/:provider/callback", AccountsController, :callback)
  end

  scope "/admin", ExAdmin do
    pipe_through([:browser, :basic_auth])
    admin_routes()
  end

  scope "/admin2", SanbaseWeb do
    pipe_through([:browser, :basic_auth])
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
    get("/api_metric_name_mapping", MetricNameController, :api_metric_name_mapping)
    get("/projects_data", ProjectDataController, :data)
    post("/stripe_webhook", StripeController, :webhook)
  end

  scope "/", SanbaseWeb do
    pipe_through(:api)

    get("/get_routed_conn", RootController, :get_routed_conn)
  end

  scope "/", SanbaseWeb do
    pipe_through(:browser)

    get("/consent", RootController, :consent)
  end

  get("/", SanbaseWeb.RootController, :healthcheck)

  def log_headers_plug(conn, _opts) do
    remote_ip = to_string(:inet_parse.ntoa(conn.remote_ip))
    req_headers = conn.req_headers

    forwarded_headers =
      req_headers
      |> Enum.filter(fn {k, _v} ->
        header = String.downcase(k)
        header in ["forwarded", "x-forwarded-for", "x-client-ip", "x-real-ip"]
      end)

    if forwarded_headers do
      Logger.info("Forwarded headers for #{remote_ip}:  #{inspect(forwarded_headers)}")
    end

    conn
  end
end

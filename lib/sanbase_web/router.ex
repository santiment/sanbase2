defmodule SanbaseWeb.Router do
  use SanbaseWeb, :router

  def handle_errors(conn, %{kind: _kind, reason: _reason, stack: _stack}) do
    send_resp(conn, conn.status, "Something went wrong")
  end

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
    plug(:fetch_session)
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
    use Plug.ErrorHandler

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
      max_complexity: 10_000,
      log_level: :info,
      before_send: {SanbaseWeb.Graphql.AbsintheBeforeSend, :before_send}
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

  scope "/", SanbaseWeb do
    pipe_through(:browser)

    get("/consent", RootController, :consent)
  end

  get("/", SanbaseWeb.RootController, :healthcheck)
end

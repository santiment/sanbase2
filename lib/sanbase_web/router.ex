defmodule SanbaseWeb.Router do
  # credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies
  use SanbaseWeb, :router

  import SanbaseWeb.AdminUserAuth

  pipeline :admin_pod_only do
    plug(SanbaseWeb.Plug.AdminPodOnly)
  end

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {SanbaseWeb.Layouts, :root})
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

  pipeline :admin_email_auth do
    plug(SanbaseWeb.Plug.AdminEmailAuthPlug)
  end

  pipeline :admin do
    plug(SanbaseWeb.GenericAdminAssignRoutes)
    plug(:put_layout, html: {SanbaseWeb.Layouts, :admin})
  end

  scope "/auth", SanbaseWeb do
    pipe_through(:browser)

    get("/delete", AuthController, :delete)
    get("/:provider", AuthController, :request)
    get("/:provider/callback", AuthController, :callback)
  end

  scope "/forms", SanbaseWeb do
    pipe_through(:browser)
    live("/", FormsLive)
    live("/suggest_ecosystems", SuggestEcosystemLabelsChangeLive)
    live("/suggest_github_organizations", SuggestGithubOrganizationsLive)
  end

  scope "/admin", SanbaseWeb do
    pipe_through([
      :admin_pod_only,
      :browser,
      :assign_current_user_or_redirect,
      :assign_current_user_roles,
      :ensure_user_has_admin_panel_role,
      :admin
    ])

    import Phoenix.LiveDashboard.Router

    # Project Changelog routes
    live("/project_changelog", ProjectChangelogLive)

    live("/academy_qa", AcademyQALive)

    scope "/metric_registry" do
      live_session :require_authenticated_user,
        on_mount: [
          {SanbaseWeb.AdminUserAuth, :ensure_authenticated},
          {SanbaseWeb.AdminUserAuth, :extract_and_assign_current_user_roles},
          {SanbaseWeb.AdminUserAuth, :ensure_user_has_metric_registry_role}
        ] do
        live("/", MetricRegistryIndexLive)
        live("/change_suggestions", MetricRegistryChangeSuggestionsLive)
        live("/show/:id", MetricRegistryShowLive)
        live("/edit/:id", MetricRegistryFormLive, :edit)
        live("/history/:id", MetricRegistryHistoryLive)
        live("/diff/:id", MetricRegistryDiffLive)
        live("/new", MetricRegistryFormLive, :new)
        live("/sync", MetricRegistrySyncLive, :new)
        live("/sync_runs", MetricRegistrySyncRunsLive, :new)
        live("/sync/:sync_type/:uuid", MetricRegistrySyncRunDetailsLive, :new)
        live("/display_order", MetricDisplayOrderLive)
        live("/display_order/show/:metric_id", MetricDisplayOrderShowLive)
        live("/display_order/edit/:metric_id", MetricDisplayOrderFormLive, :edit)
        live("/display_order/new", MetricDisplayOrderNewLive, :new)
        live("/categories", CategoryLive.Index)
        live("/categories/new", CategoryLive.Form, :new)
        live("/categories/edit/:id", CategoryLive.Form, :edit)
        live("/groups", GroupLive.Index)
        live("/groups/new", GroupLive.Form, :new)
        live("/groups/edit/:id", GroupLive.Form, :edit)
        live("/changelog", MetricChangelogLive)
      end
    end

    scope "/tweets_prediction" do
      live_session :tweets_prediction_authenticated_user,
        on_mount: [
          {SanbaseWeb.AdminUserAuth, :ensure_authenticated},
          {SanbaseWeb.AdminUserAuth, :extract_and_assign_current_user_roles}
        ] do
        live("/", TweetsPredictionLive)
      end
    end

    scope "/price_predictions" do
      live("/", PricePredictionsLive)
    end

    scope "/disagreement_tweets" do
      live_session :disagreement_tweets_authenticated_user,
        on_mount: [
          {SanbaseWeb.AdminUserAuth, :ensure_authenticated},
          {SanbaseWeb.AdminUserAuth, :extract_and_assign_current_user_roles}
        ] do
        live("/", DisagreementTweetsLive)
      end
    end

    live_dashboard("/dashboard", metrics: SanbaseWeb.Telemetry, ecto_repos: [Sanbase.Repo])
    live("/admin_forms", AdminFormsLive)
    live("/monitored_twitter_handle_live", MonitoredTwitterHandleLive)
    live("/suggest_ecosystems_admin_live", SuggestEcosystemLabelsChangeAdminLive)
    live("/suggest_github_organizations_admin_live", SuggestGithubOrganizationsAdminLive)
    live("/upload_image_live", UploadImageLive)
    live("/uploaded_images_live", UploadedImagesLive)

    live "/notifications/manual/discord", NotificationsLive.ManualDiscordFormLive
    live "/notifications/manual/email", NotificationsLive.ManualEmailFormLive
    live "/notifications/digest/:action", NotificationsLive.DigestFormLive
    # Add route for scheduled deprecation notification UI
    live "/scheduled_deprecations", ScheduledDeprecationIndexLive, :index
    live "/scheduled_deprecations/new", ScheduledDeprecationLive, :new

    resources("/reports", ReportController)
    resources("/sheets_templates", SheetsTemplateController)
    resources("/webinars", WebinarController)
    resources("/custom_plans", CustomPlanController)

    get("/", GenericAdminController, :home)
    get("/generic/search", GenericAdminController, :search)
    get("/generic/show_action", GenericAdminController, :show_action)
    resources("/generic", GenericAdminController)

    live("/user_stats", UserStatsLive)
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

    forward(
      "/graphiql_advanced",
      # Use own version of the plug with fixed XSS vulnerability
      Absinthe.Plug.GraphiQL,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      socket: SanbaseWeb.UserSocket,
      document_providers: [
        SanbaseWeb.Graphql.DocumentProvider,
        Absinthe.Plug.DocumentProvider.Default
      ],
      analyze_complexity: true,
      max_complexity: 50_000,
      interface: :advanced,
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
    pipe_through([:browser])
    # A LiveView for exploring the available metrics and a GET
    # REST endpoint for downloading a CSV with the available metrics
    live("/available_metrics", AvailableMetricsLive)
    live("/available_metrics/:metric", MetricDetailsLive)

    get("/export_available_metrics", AvailableMetricsController, :export)
  end

  scope "/admin_auth", SanbaseWeb do
    pipe_through([:admin_pod_only, :browser, :admin_email_auth])
    get("/email_login", AdminAuthController, :handle_admin_email_auth)
  end

  scope "/", SanbaseWeb do
    pipe_through([:browser, :admin_pod_only])

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{SanbaseWeb.AdminUserAuth, :redirect_if_user_is_authenticated}] do
      live("/admin_auth/login", AdminAuthenticateLive)
      get("/admin_auth/logout", AdminAuthController, :logout)
    end
  end

  scope "/", SanbaseWeb do
    get("/metric_registry_export", MetricRegistryController, :export_json)
    post("/sync_metric_registry", MetricRegistryController, :sync)

    post(
      "/mark_metric_registry_sync_as_finished/:sync_uuid",
      MetricRegistryController,
      :mark_sync_as_completed
    )

    get("/api_metric_name_mapping", MetricNameController, :api_metric_name_mapping)
    get("/projects_data", DataController, :projects_data)
    get("/projects_twitter_handles", DataController, :projects_twitter_handles)
    get("/monitored_twitter_handles/:secret", DataController, :monitored_twitter_handles)
    get("/ecosystems_data", DataController, :ecosystems_data)
    get("/clickhouse_metrics_metadata", DataController, :clickhouse_metrics_metadata)

    get(
      "/ecosystem_github_organization_mapping",
      DataController,
      :ecosystem_github_organization_mapping
    )

    get("/santiment_team_members/:secret", DataController, :santiment_team_members)
    get("/cryptocompare_asset_mapping", CryptocompareAssetMappingController, :data)
    post("/stripe_webhook", StripeController, :webhook)
    post("/mailjet/webhook", MailjetController, :webhook)

    post("/projects_data_validator_webhook", RepoReaderController, :validator_webhook)
    post("/projects_data_reader_webhook/:secret", RepoReaderController, :reader_webhook)
  end

  scope "/", SanbaseWeb do
    pipe_through(:api)

    get("/get_routed_conn", RootController, :get_routed_conn)
  end

  get("/", SanbaseWeb.RootController, :healthcheck)
  get("/healthcheck", SanbaseWeb.RootController, :healthcheck)
end

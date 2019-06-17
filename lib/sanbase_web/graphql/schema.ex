defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias SanbaseWeb.Graphql.Resolvers.{
    AccountResolver,
    SocialDataResolver,
    MarketSegmentResolver,
    ApikeyResolver,
    UserSettingsResolver,
    TelegramResolver,
    UserTriggerResolver,
    SignalsHistoricalActivityResolver,
    FeaturedItemResolver,
    UserFollowerResolver,
    TimelineEventResolver
  }

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Complexity

  alias SanbaseWeb.Graphql.Middlewares.{
    BasicAuth,
    JWTAuth,
    TimeframeRestriction,
    ApiUsage,
    CreateOrDeleteSession
  }

  import_types(Absinthe.Plug.Types)
  import_types(Absinthe.Type.Custom)
  import_types(SanbaseWeb.Graphql.TagTypes)
  import_types(SanbaseWeb.Graphql.CustomTypes)
  import_types(SanbaseWeb.Graphql.AccountTypes)
  import_types(SanbaseWeb.Graphql.TwitterTypes)
  import_types(SanbaseWeb.Graphql.EtherbiTypes)
  import_types(SanbaseWeb.Graphql.InsightTypes)
  import_types(SanbaseWeb.Graphql.TransactionTypes)
  import_types(SanbaseWeb.Graphql.FileTypes)
  import_types(SanbaseWeb.Graphql.UserListTypes)
  import_types(SanbaseWeb.Graphql.MarketSegmentTypes)
  import_types(SanbaseWeb.Graphql.ElasticsearchTypes)
  import_types(SanbaseWeb.Graphql.ClickhouseTypes)
  import_types(SanbaseWeb.Graphql.ExchangeTypes)
  import_types(SanbaseWeb.Graphql.UserSettingsTypes)
  import_types(SanbaseWeb.Graphql.UserTriggerTypes)
  import_types(SanbaseWeb.Graphql.CustomTypes.JSON)
  import_types(SanbaseWeb.Graphql.PaginationTypes)
  import_types(SanbaseWeb.Graphql.SignalsHistoricalActivityTypes)
  import_types(SanbaseWeb.Graphql.TimelineEventTypes)
  import_types(SanbaseWeb.Graphql.Schema.SocialDataQueries)
  import_types(SanbaseWeb.Graphql.Schema.WatchlistQueries)
  import_types(SanbaseWeb.Graphql.Schema.ProjectQueries)
  import_types(SanbaseWeb.Graphql.Schema.InsightQueries)
  import_types(SanbaseWeb.Graphql.Schema.TechIndicatorsQueries)
  import_types(SanbaseWeb.Graphql.Schema.PriceQueries)
  import_types(SanbaseWeb.Graphql.Schema.GithubQueries)
  import_types(SanbaseWeb.Graphql.Schema.BlockchainQueries)

  def dataloader() do
    alias SanbaseWeb.Graphql.{
      SanbaseRepo,
      SanbaseDataloader
    }

    # 11 seconds is 1s more than the influxdb timeout
    Dataloader.new(timeout: :timer.seconds(11))
    |> Dataloader.add_source(SanbaseRepo, SanbaseRepo.data())
    |> Dataloader.add_source(SanbaseDataloader, SanbaseDataloader.data())
  end

  def context(ctx) do
    ctx
    |> Map.put(:loader, dataloader())
  end

  def plugins do
    [
      Absinthe.Middleware.Dataloader | Absinthe.Plugin.defaults()
    ]
  end

  def middleware(middlewares, field, object) do
    prometeheus_middlewares =
      SanbaseWeb.Graphql.Prometheus.HistogramInstrumenter.instrument(middlewares, field, object)
      |> SanbaseWeb.Graphql.Prometheus.CounterInstrumenter.instrument(field, object)

    case object.identifier do
      :query ->
        [ApiUsage | prometeheus_middlewares]

      _ ->
        prometeheus_middlewares
    end
  end

  query do
    import_fields(:social_data_queries)
    import_fields(:user_list_queries)
    import_fields(:project_queries)
    import_fields(:project_eth_spent_queries)
    import_fields(:insight_queries)
    import_fields(:tech_indicators_queries)
    import_fields(:price_queries)
    import_fields(:github_queries)
    import_fields(:blockchain_queries)

    @desc "Returns the user currently logged in."
    field :current_user, :user do
      resolve(&AccountResolver.current_user/3)
    end

    @desc "Fetch all market segments."
    field :all_market_segments, list_of(:market_segment) do
      cache_resolve(&MarketSegmentResolver.all_market_segments/3)
    end

    @desc "Fetch ERC20 projects' market segments."
    field :erc20_market_segments, list_of(:market_segment) do
      cache_resolve(&MarketSegmentResolver.erc20_market_segments/3)
    end

    @desc "Fetch currency projects' market segments."
    field :currencies_market_segments, list_of(:market_segment) do
      cache_resolve(&MarketSegmentResolver.currencies_market_segments/3)
    end

    @desc """
    Get a URL for deep-linking sanbase and telegram accounts. It carries a unique
    random token that is associated with the user. The link leads to a telegram chat
    with Santiment's notification bot. When the `Start` button is pressed, telegram
    and sanbase accounts are linked and the user can receive sanbase signals in telegram.
    """
    field :get_telegram_deep_link, :string do
      middleware(JWTAuth)
      resolve(&TelegramResolver.get_telegram_deep_link/3)
    end

    @desc "Get signal trigger by its id"
    field :get_trigger_by_id, :user_trigger do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&UserTriggerResolver.get_trigger_by_id/3)
    end

    @desc "Get public signal triggers by user_id"
    field :public_triggers_for_user, list_of(:user_trigger) do
      arg(:user_id, non_null(:id))

      resolve(&UserTriggerResolver.public_triggers_for_user/3)
    end

    @desc "Get all public signal triggers"
    field :all_public_triggers, list_of(:user_trigger) do
      resolve(&UserTriggerResolver.all_public_triggers/3)
    end

    @desc "Get historical trigger points"
    field :historical_trigger_points, list_of(:json) do
      arg(:cooldown, :string)
      arg(:settings, non_null(:json))

      cache_resolve(&UserTriggerResolver.historical_trigger_points/3)
    end

    @desc ~s"""
    Get current user's history of executed signals with cursor pagination.
    * `cursor` argument is an object with: type `BEFORE` or `AFTER` and `datetime`.
      - `type: BEFORE` gives those executed before certain datetime
      - `type: AFTER` gives those executed after certain datetime
    * `limit` argument defines the size of the page. Default value is 25
    """
    field :signals_historical_activity, :signal_historical_activity_paginated do
      arg(:cursor, :cursor_input)
      arg(:limit, :integer, default_value: 25)

      middleware(JWTAuth)

      resolve(&SignalsHistoricalActivityResolver.fetch_historical_activity_for/3)
    end

    field :timeline_events, list_of(:timeline_events_paginated) do
      arg(:cursor, :cursor_input)
      arg(:limit, :integer, default_value: 25)

      middleware(JWTAuth)

      resolve(&TimelineEventResolver.timeline_events/3)
    end

    field :featured_insights, list_of(:post) do
      cache_resolve(&FeaturedItemResolver.insights/3)
    end

    field :featured_watchlists, list_of(:user_list) do
      cache_resolve(&FeaturedItemResolver.watchlists/3)
    end

    field :featured_user_triggers, list_of(:user_trigger) do
      cache_resolve(&FeaturedItemResolver.user_triggers/3)
    end
  end

  mutation do
    import_fields(:user_list_mutations)
    import_fields(:insight_mutations)

    field :eth_login, :login do
      arg(:signature, non_null(:string))
      arg(:address, non_null(:string))
      arg(:message_hash, non_null(:string))

      resolve(&AccountResolver.eth_login/2)
      middleware(CreateOrDeleteSession)
    end

    field :email_login, :email_login_request do
      arg(:email, non_null(:string))
      arg(:username, :string)
      arg(:consent, :string)

      resolve(&AccountResolver.email_login/2)
    end

    field :email_login_verify, :login do
      arg(:email, non_null(:string))
      arg(:token, non_null(:string))

      resolve(&AccountResolver.email_login_verify/2)
      middleware(CreateOrDeleteSession)
    end

    field :logout, :logout do
      middleware(JWTAuth, allow_access: true)
      resolve(fn _, _ -> {:ok, %{success: true}} end)
      middleware(CreateOrDeleteSession)
    end

    field :email_change_verify, :login do
      arg(:email_candidate, non_null(:string))
      arg(:token, non_null(:string))

      resolve(&AccountResolver.email_change_verify/2)
    end

    field :change_email, :email_login_request do
      arg(:email, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.change_email/3)
    end

    field :change_username, :user do
      arg(:username, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.change_username/3)
    end

    @desc ~s"""
    Add the given `address` for the currently logged in user. The `signature` and
    `message_hash` are passed to the `web3.eth.accounts.recover` function to recover
    the Ethereum address. If it is the same as the passed in the argument then the
    user has access to this address and has indeed signed the message
    """
    field :add_user_eth_address, :user do
      arg(:signature, non_null(:string))
      arg(:address, non_null(:string))
      arg(:message_hash, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.add_user_eth_address/3)
    end

    @desc ~s"""
    Remove the given `address` for the currently logged in user. This can only be done
    if this `address` is not the only mean for the user to log in. It can be removed
    only if there is an email set or there is another ethereum address added.
    """
    field :remove_user_eth_address, :user do
      arg(:address, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.remove_user_eth_address/3)
    end

    @desc ~s"""
    Update the terms and condition the user accepts. The `accept_privacy_policy`
    must be accepted (must equal `true`) in order for the account to be considered
    activated.
    """
    field :update_terms_and_conditions, :user do
      arg(:privacy_policy_accepted, :boolean)
      arg(:marketing_accepted, :boolean)

      # Allow this mutation to be executed when the user has not accepted the privacy policy.
      middleware(JWTAuth, allow_access: true)
      resolve(&AccountResolver.update_terms_and_conditions/3)
    end

    @desc ~s"""
    Generates a new apikey. There could be more than one apikey per user at every
    given time. Only JWT authenticated users can generate apikeys. The apikeys can
     be retrieved via the `apikeys` fields of the `user` GQL type.
    """
    field :generate_apikey, :user do
      middleware(JWTAuth)
      resolve(&ApikeyResolver.generate_apikey/3)
    end

    @desc ~s"""
    Revoke the given apikey if only the currently logged in user is the owner of the
    apikey. Only JWT authenticated users can revoke apikeys. You cannot revoke the apikey
    using the apikey.
    """
    field :revoke_apikey, :user do
      arg(:apikey, non_null(:string))

      middleware(JWTAuth)
      resolve(&ApikeyResolver.revoke_apikey/3)
    end

    @desc "Allow/Dissallow to receive notifications in email/telegram channel"
    field :settings_toggle_channel, :user_settings do
      arg(:signal_notify_telegram, :boolean)
      arg(:signal_notify_email, :boolean)

      middleware(JWTAuth)
      resolve(&UserSettingsResolver.settings_toggle_channel/3)
    end

    @desc "Change subscription to Santiment newsletter"
    field :change_newsletter_subscription, :user_settings do
      arg(:newsletter_subscription, :newsletter_subscription_type)

      middleware(JWTAuth)
      resolve(&UserSettingsResolver.change_newsletter_subscription/3)
    end

    @desc """
    Revoke the telegram deep link for the currently logged in user if present.
    The link will continue to work and following it will send a request to sanbase,
    but the used token will no longer be paired with the user.
    """
    field :revoke_telegram_deep_link, :boolean do
      middleware(JWTAuth)
      resolve(&TelegramResolver.revoke_telegram_deep_link/3)
    end

    @desc """
    Create signal trigger described by `trigger` json field.
    Returns the newly created trigger.
    """
    field :create_trigger, :user_trigger do
      arg(:title, non_null(:string))
      arg(:description, :string)
      arg(:icon_url, :string)
      arg(:is_public, :boolean)
      arg(:is_active, :boolean)
      arg(:is_repeating, :boolean)
      arg(:cooldown, :string)
      arg(:tags, list_of(:string))
      arg(:settings, non_null(:json))

      middleware(JWTAuth)
      resolve(&UserTriggerResolver.create_trigger/3)
    end

    @desc """
    Update signal trigger by its id.
    Returns the updated trigger.
    """
    field :update_trigger, :user_trigger do
      arg(:id, non_null(:integer))
      arg(:title, :string)
      arg(:description, :string)
      arg(:settings, :json)
      arg(:icon_url, :string)
      arg(:cooldown, :string)
      arg(:is_active, :boolean)
      arg(:is_public, :boolean)
      arg(:is_repeating, :boolean)
      arg(:tags, list_of(:string))

      middleware(JWTAuth)
      resolve(&UserTriggerResolver.update_trigger/3)
    end

    @desc """
    Remove signal trigger by its id.
    Returns the removed trigger on success.
    """
    field :remove_trigger, :user_trigger do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&UserTriggerResolver.remove_trigger/3)
    end

    @desc "Follow chosen user"
    field :follow, :user do
      arg(:user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&UserFollowerResolver.follow/3)
    end

    @desc "Unfollow chosen user"
    field :unfollow, :user do
      arg(:user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&UserFollowerResolver.unfollow/3)
    end
  end
end

defmodule SanbaseWeb.Graphql.UserTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]
  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.SanbaseRepo

  alias SanbaseWeb.Graphql.Resolvers.{
    ApikeyResolver,
    BillingResolver,
    EthAccountResolver,
    InsightResolver,
    LinkedUserResolver,
    UserChartConfigurationResolver,
    UserListResolver,
    UserResolver,
    UserSettingsResolver,
    UserTriggerResolver,
    SanbaseNFTResolver,
    UserAffiliateDetailsResolver,
    QueriesResolver
  }

  enum :user_role do
    value(:san_family)
    value(:san_team)
  end

  enum :api_call_auth_method do
    value(:all)
    value(:apikey)
    value(:basic)
    value(:jwt)
  end

  @desc ~s"""
  Shows what is the access level of the user for a given flag.
  Access levels can be:
    - Early Access - ALPHA and BETA
    - Standard Access - RELEASED. Default for everyone

  When a user has early access set (for metrics, for features, etc.) the user
  can access that metric/feature before it is released for everyone.
  The access level by default is RELEASED. It can be changed only manually by a
  Santiment Administrator.
  """
  enum :user_access_level do
    value(:alpha)
    value(:beta)
    value(:released)
  end

  input_object :user_selector_input_object do
    field(:id, :id)
    field(:email, :string)
    field(:username, :string)
  end

  object :public_user do
    field(:id, non_null(:id))

    field :email, :string do
      resolve(&UserResolver.email/3)
    end

    field(:name, :string)
    field(:username, :string)
    field(:description, :string)

    field(:avatar_url, :string)
    field(:website_url, :string)
    field(:twitter_handle, :string)

    field :is_moderator, :boolean do
      resolve(&UserResolver.moderator?/3)
    end

    field :is_santiment_team_member, :boolean do
      resolve(&UserResolver.santiment_team_member?/3)
    end

    field :votes_stats, :votes_stats do
      resolve(&UserResolver.votes_stats/3)
    end

    field :entities_stats, :entities_stats do
      resolve(&UserResolver.entities_stats/3)
    end

    field :triggers, list_of(:trigger) do
      cache_resolve(&UserTriggerResolver.public_triggers/3, ttl: 60)
    end

    field :chart_configurations, list_of(:chart_configuration) do
      cache_resolve(&UserChartConfigurationResolver.public_chart_configurations/3, ttl: 60)
    end

    field :following, :follower_data do
      resolve(&UserResolver.following/3)
    end

    field :followers, :follower_data do
      resolve(&UserResolver.followers/3)
    end

    field :subscriptions, list_of(:public_subscription_plan) do
      resolve(&BillingResolver.public_user_subscriptions/3)
    end

    field :insights, list_of(:post) do
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:from, :datetime)
      arg(:to, :datetime)
      arg(:page, :integer, default_value: 1)
      arg(:page_size, :integer, default_value: 20)

      cache_resolve(&InsightResolver.public_insights/3, ttl: 60)
    end

    field :insights_count, :public_insights_count do
      cache_resolve(&InsightResolver.insights_count/3, ttl: 60)
    end

    field :watchlists, list_of(:user_list) do
      arg(:type, :watchlist_type_enum, default_value: :project)

      cache_resolve(&UserListResolver.public_watchlists/3, ttl: 60)
    end

    field :dashboards, list_of(:dashboard) do
      cache_resolve(&QueriesResolver.get_all_user_public_dashboards/3, ttl: 60)
    end
  end

  object :user_promo_code do
    field(:campaign, :string)
    field(:coupon, :string)
    field(:percent_off, :integer)
    field(:redeem_by, :datetime)
    field(:max_redemptions, :integer)
    field(:times_redeemed, :integer)
    field(:data, :json)
  end

  object :queries_executions_info do
    field(:credits_available_month, non_null(:integer))
    field(:credits_spent_month, non_null(:integer))
    field(:credits_remaining_month, non_null(:integer))
    field(:queries_executed_month, non_null(:integer))
    field(:queries_executed_day, non_null(:integer))
    field(:queries_executed_hour, non_null(:integer))
    field(:queries_executed_minute, non_null(:integer))
    field(:queries_executed_day_limit, non_null(:integer))
    field(:queries_executed_hour_limit, non_null(:integer))
    field(:queries_executed_minute_limit, non_null(:integer))
  end

  object :user do
    field(:id, non_null(:id))
    field(:email, :string)
    field(:name, :string)
    field(:username, :string)
    field(:consent_id, :string)
    field(:privacy_policy_accepted, :boolean)
    field(:marketing_accepted, :boolean)
    field(:first_login, :boolean, default_value: false)
    field(:avatar_url, :string)
    field(:stripe_customer_id, :string)
    field(:inserted_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))
    field(:description, :string)
    field(:website_url, :string)
    field(:twitter_handle, :string)

    field :votes_stats, :votes_stats do
      resolve(&UserResolver.votes_stats/3)
    end

    field :entities_stats, :entities_stats do
      resolve(&UserResolver.entities_stats/3)
    end

    field :queries_executions_info, :queries_executions_info do
      resolve(&UserResolver.queries_executions_info/3)
    end

    field :promo_codes, list_of(:user_promo_code) do
      resolve(&UserResolver.user_promo_codes/3)
    end

    field :is_moderator, :boolean do
      resolve(&UserResolver.moderator?/3)
    end

    field :is_santiment_team_member, :boolean do
      resolve(&UserResolver.santiment_team_member?/3)
    end

    field :permissions, :access_level do
      resolve(&UserResolver.permissions/3)
    end

    field :metric_access_level, non_null(:user_access_level) do
      resolve(&UserResolver.metric_access_level/3)
    end

    field :feature_access_level, non_null(:user_access_level) do
      resolve(&UserResolver.feature_access_level/3)
    end

    field :san_balance, :float do
      cache_resolve(&UserResolver.san_balance/3)
    end

    field :primary_user_sanbase_subscription, :subscription_plan do
      resolve(&LinkedUserResolver.primary_user_sanbase_subscription/3)
    end

    field :primary_user, :public_user do
      resolve(&LinkedUserResolver.get_primary_user/3)
    end

    field :secondary_users, list_of(:public_user) do
      resolve(&LinkedUserResolver.get_secondary_users/3)
    end

    @desc ~s"""
    A list of ethereum addresses owned by the user. A special message needs to be
    signed in order to be confirmed that the address belongs to the user.
    The combined SAN balance of the addresses is used for the `san_balance`
    """
    field(:eth_accounts, list_of(:eth_account), resolve: dataloader(SanbaseRepo))

    @desc ~s"""
    A list of api keys. They are used by providing `Authorization` header to the
    HTTP request with the value `Apikey <apikey>` (case sensitive). To generate
    or revoke api keys check the `generateApikey` and `revokeApikey` mutations.

    Using an apikey gives access to the queries, but not to the mutations. Every
    api key has the same SAN balance and subsription as the whole account
    """
    field :apikeys, list_of(:string) do
      resolve(&ApikeyResolver.apikeys_list/3)
    end

    field :settings, :user_settings do
      resolve(&UserSettingsResolver.settings/3)
    end

    field :triggers, list_of(:trigger) do
      resolve(&UserTriggerResolver.triggers/3)
    end

    field :chart_configurations, list_of(:chart_configuration) do
      resolve(&UserChartConfigurationResolver.chart_configurations/3)
    end

    field :following, :follower_data do
      resolve(&UserResolver.following/3)
    end

    field :followers, :follower_data do
      resolve(&UserResolver.followers/3)
    end

    field :following2, :follower_data2 do
      resolve(&UserResolver.following2/3)
    end

    field :followers2, :follower_data2 do
      resolve(&UserResolver.followers2/3)
    end

    field :insights_count, :insights_count do
      cache_resolve(&InsightResolver.insights_count/3, ttl: 60)
    end

    field :insights, list_of(:post) do
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:page, :integer, default_value: 1)
      arg(:page_size, :integer, default_value: 20)

      resolve(&InsightResolver.insights/3)
    end

    field :watchlists, list_of(:user_list) do
      arg(:type, :watchlist_type_enum, default_value: :project)

      cache_resolve(&UserListResolver.watchlists/3, ttl: 60)
    end

    field :dashboards, list_of(:dashboard) do
      cache_resolve(&QueriesResolver.get_all_current_user_dashboards/3, ttl: 60)
    end

    field :chats, list_of(:chat_summary) do
      resolve(&SanbaseWeb.Graphql.Resolvers.ChatResolver.my_chats/3)
    end

    field :subscriptions, list_of(:subscription_plan) do
      resolve(&BillingResolver.subscriptions/3)
    end

    field :is_eligible_for_sanbase_trial, :boolean do
      resolve(&BillingResolver.eligible_for_sanbase_trial?/3)
    end

    field :is_eligible_for_api_trial, :boolean do
      resolve(&BillingResolver.eligible_for_api_trial?/3)
    end

    field :san_credit_balance, :float do
      resolve(&BillingResolver.san_credit_balance/3)
    end

    field :sanbase_nft, :sanbase_nft do
      resolve(&SanbaseNFTResolver.sanbase_nft/3)
    end

    @desc ~s"""
    Timeseries data of api calls count per interval in a given time range.
    """
    field :api_calls_history, list_of(:api_call_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:auth_method, :api_call_auth_method, default_value: :apikey)
      arg(:interval, :interval, default_value: "1d")

      cache_resolve(&UserResolver.api_calls_history/3)
    end

    @desc ~s"""
    Timeseries data of api calls count per interval in a given time range.
    """
    field :api_calls_count, :integer do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:auth_method, :api_call_auth_method, default_value: :apikey)

      cache_resolve(&UserResolver.api_calls_count/3)
    end

    field :are_user_affiliate_datails_submitted, :boolean do
      resolve(&UserAffiliateDetailsResolver.are_user_affiliate_datails_submitted/3)
    end

    field :signup_datetime, :datetime do
      resolve(&UserResolver.signup_datetime/3)
    end
  end

  object :entities_stats do
    field(:insights_created, :integer)
    field(:queries_created, :integer)
    field(:dashboards_created, :integer)
    field(:chart_configurations_created, :integer)
    field(:alerts_created, :integer)
    field(:screeners_created, :integer)
    field(:project_watchlists_created, :integer)
    field(:address_watchlists_created, :integer)
  end

  object :votes_stats do
    field(:insight_votes, :integer)
    field(:watchlist_votes, :integer)
    field(:chart_configuration_votes, :integer)
    field(:alert_votes, :integer)
    field(:dashboard_votes, :integer)
    field(:query_votes, :integer)
    field(:total_votes, :integer)
  end

  object :relays_quota do
    field(:global_relays_left, :integer)
    field(:global_relays_quota, :integer)
    field(:global_relays_used, :integer)
    field(:proposal_relays_left, :integer)
    field(:proposal_relays_quota, :integer)
    field(:proposal_relays_used, :integer)
    field(:vote_relays_left, :integer)
    field(:vote_relays_quota, :integer)
    field(:vote_relays_used, :integer)
    field(:can_relay_proposal, :boolean)
    field(:can_relay_vote, :boolean)
  end

  object :public_insights_count do
    field(:total_count, :integer)
    field(:paywall_count, :integer)
    field(:pulse_count, :integer)
  end

  object :insights_count do
    field(:total_count, :integer)
    field(:draft_count, :integer)
    field(:paywall_count, :integer)
    field(:pulse_count, :integer)
  end

  enum :access_restriction_filter_enum do
    value(:metric)
    value(:query)
    value(:signal)
  end

  object :docs_object do
    field(:link, non_null(:string))
  end

  object :access_restriction do
    field(:type, non_null(:string))
    field(:name, non_null(:string))
    field(:human_readable_name, non_null(:string))
    field(:internal_name, non_null(:string))
    field(:min_interval, :string)
    field(:is_restricted, non_null(:boolean))
    field(:is_accessible, non_null(:boolean))
    field(:restricted_from, :datetime)
    field(:restricted_to, :datetime)
    field(:is_deprecated, non_null(:boolean))
    field(:hard_deprecate_after, :datetime)
    field(:docs, list_of(:docs_object))
    field(:available_selectors, list_of(:selector_name))
    field(:required_selectors, list_of(list_of(:selector_name)))
    # only metrics have status, for queries and signals it is nil
    field(:status, :string)
  end

  object :api_call_data do
    field(:datetime, non_null(:datetime))
    field(:api_calls_count, non_null(:integer))
  end

  object :sanbase_nft do
    field(:has_valid_nft, non_null(:boolean))
    field(:has_non_valid_nft, :boolean)
    field(:nft_data, non_null(list_of(:nft_data)))
    field(:nft_count, non_null(:integer))
    field(:non_valid_nft_count, non_null(:integer))
  end

  object :nft_data do
    field(:address, :string)
    field(:token_ids, list_of(:integer))
    field(:non_valid_token_ids, list_of(:integer))
  end

  @desc ~s"""
  A type describing an Ethereum address. Beside the address itself it returns
  the SAN balance of that address.
  """
  object :eth_account do
    field(:address, non_null(:string))

    field :san_balance, non_null(:float) do
      cache_resolve(&EthAccountResolver.san_balance/3)
    end
  end

  object :access_level do
    field(:api, non_null(:boolean))
    field(:sanbase, non_null(:boolean))
    field(:spreadsheet, non_null(:boolean))
  end

  object :follower_data do
    field(:count, non_null(:integer))
    field(:users, non_null(list_of(:public_user)))
  end

  object :follower_data2 do
    field(:count, non_null(:integer))
    field(:users, non_null(list_of(:user_follower)))
  end

  object :user_follower do
    field(:user_id, non_null(:id))
    field(:follower_id, non_null(:id))
    field(:is_notification_disabled, :boolean)
    field(:user, :public_user)
  end
end

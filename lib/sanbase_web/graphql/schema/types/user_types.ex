defmodule SanbaseWeb.Graphql.UserTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]
  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.SanbaseRepo

  alias SanbaseWeb.Graphql.Resolvers.{
    ApikeyResolver,
    BillingResolver,
    DashboardResolver,
    EthAccountResolver,
    InsightResolver,
    LinkedUserResolver,
    UserChartConfigurationResolver,
    UserListResolver,
    UserResolver,
    UserSettingsResolver,
    UserTriggerResolver
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
    field(:avatar_url, :string)

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

    field :dashboards, list_of(:dashboard_schema) do
      cache_resolve(&DashboardResolver.user_public_dashboards/3, ttl: 60)
    end
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

    field :is_moderator, :boolean do
      resolve(&UserResolver.is_moderator/3)
    end

    field :permissions, :access_level do
      resolve(&UserResolver.permissions/3)
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

    field :dashboards, list_of(:dashboard_schema) do
      cache_resolve(&DashboardResolver.user_dashboards/3, ttl: 60)
    end

    field :subscriptions, list_of(:subscription_plan) do
      resolve(&BillingResolver.subscriptions/3)
    end

    field :is_eligible_for_sanbase_trial, :boolean do
      resolve(&BillingResolver.eligible_for_sanbase_trial?/3)
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

  object :access_restriction do
    field(:type, non_null(:string))
    field(:name, non_null(:string))
    field(:min_interval, :string)
    field(:is_restricted, non_null(:boolean))
    field(:is_accessible, non_null(:boolean))
    field(:restricted_from, :datetime)
    field(:restricted_to, :datetime)
  end

  object :api_call_data do
    field(:datetime, non_null(:datetime))
    field(:api_calls_count, non_null(:integer))
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
    field(:sandata, non_null(:boolean))
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

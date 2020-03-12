defmodule Sanbase.Factory do
  use ExMachina.Ecto, repo: Sanbase.Repo

  alias Sanbase.Tag
  alias Sanbase.UserList
  alias Sanbase.Auth.{User, UserSettings, Role, UserRole}
  alias Sanbase.Insight.Post
  alias Sanbase.Comment

  alias Sanbase.Model.{
    Project,
    ExchangeAddress,
    ProjectEthAddress,
    ProjectBtcAddress,
    Infrastructure,
    MarketSegment,
    LatestCoinmarketcapData,
    Currency,
    Ico,
    IcoCurrency
  }

  alias Sanbase.Signal.{UserTrigger, HistoricalActivity}
  alias Sanbase.Billing.{Product, Plan, Subscription}
  alias Sanbase.Billing.Subscription.SignUpTrial
  alias Sanbase.Timeline.TimelineEvent

  def user_factory() do
    %User{
      username: :crypto.strong_rand_bytes(16) |> Base.encode16(),
      email: (:crypto.strong_rand_bytes(16) |> Base.encode16()) <> "@gmail.com",
      salt: User.generate_salt(),
      privacy_policy_accepted: true,
      san_balance: Decimal.new(0),
      san_balance_updated_at: Timex.now()
    }
  end

  def insights_fallback_user_factory() do
    %User{
      salt: User.generate_salt(),
      username: User.anonymous_user_username(),
      email: User.anonymous_user_email()
    }
  end

  def staked_user_factory() do
    %User{
      salt: User.generate_salt(),
      san_balance: Decimal.new(20_000),
      san_balance_updated_at: Timex.now(),
      privacy_policy_accepted: true
    }
  end

  def post_factory() do
    %Post{
      user: build(:user),
      title: "Awesome analysis",
      link: "http://example.com",
      text: "Text of the post",
      is_pulse: false,
      tags: [build(:tag), build(:tag)]
    }
  end

  def comment_factory() do
    %Comment{
      content: "some default comment"
    }
  end

  def tag_factory() do
    %Tag{
      name: rand_str(5)
    }
  end

  def post_no_default_user_factory() do
    %Post{
      title: "Awesome analysis",
      link: "http://example.com",
      text: "Text of the post",
      state: Post.awaiting_approval_state()
    }
  end

  def random_erc20_project_factory(attrs) do
    slug = Map.get(attrs, :slug, rand_str())

    %Project{
      name: rand_str(),
      ticker: rand_str(4),
      slug: slug,
      is_hidden: false,
      source_slug_mappings: [
        build(:source_slug_mapping, %{source: "coinmarketcap", slug: slug})
      ],
      token_decimals: 18,
      total_supply: :rand.uniform(50_000_000) + 10_000_000,
      twitter_link: "https://twitter.com/#{rand_hex_str()}",
      github_organizations: [build(:github_organization)],
      market_segments: [build(:market_segment)],
      infrastructure:
        Sanbase.Repo.get_by(Infrastructure, code: "ETH") || build(:infrastructure, %{code: "ETH"}),
      eth_addresses: [build(:project_eth_address)],
      main_contract_address: "0x" <> rand_hex_str()
    }
    |> merge_attributes(attrs)
  end

  def project_factory(attrs) do
    slug = Map.get(attrs, :slug, "santiment")

    %Project{
      name: "Santiment",
      ticker: "SAN",
      slug: slug,
      is_hidden: false,
      source_slug_mappings: [
        build(:source_slug_mapping, %{source: "coinmarketcap", slug: slug})
      ],
      token_decimals: 18,
      total_supply: 83_000_000,
      twitter_link: "https://twitter.com/#{rand_hex_str()}",
      github_organizations: [build(:github_organization)],
      market_segments: [build(:market_segment)],
      infrastructure: nil,
      eth_addresses: [build(:project_eth_address)]
    }
    |> merge_attributes(attrs)
  end

  def random_project_factory(attrs) do
    slug = Map.get(attrs, :slug, rand_str())

    %Project{
      name: rand_str(),
      ticker: rand_hex_str() |> String.upcase(),
      slug: slug,
      is_hidden: false,
      source_slug_mappings: [
        build(:source_slug_mapping, %{source: "coinmarketcap", slug: slug})
      ],
      token_decimals: 18,
      total_supply: :rand.uniform(50_000_000) + 10_000_000,
      twitter_link: "https://twitter.com/#{rand_hex_str()}",
      github_organizations: [build(:github_organization)],
      market_segments: [build(:market_segment)],
      infrastructure: nil,
      eth_addresses: [build(:project_eth_address)]
    }
    |> merge_attributes(attrs)
  end

  def source_slug_mapping_factory() do
    %Project.SourceSlugMapping{}
  end

  def social_volume_query_factory() do
    %Project.SocialVolumeQuery{}
  end

  def github_organization_factory() do
    %Project.GithubOrganization{
      organization: rand_str()
    }
  end

  def latest_cmc_data_factory() do
    %LatestCoinmarketcapData{
      coinmarketcap_id: "santiment",
      coinmarketcap_integer_id: 1807,
      rank: 100,
      price_usd: 2,
      price_btc: 0.0001 |> Decimal.from_float(),
      volume_usd: 100_000,
      update_time: Timex.now()
    }
  end

  def market_segment_factory() do
    %MarketSegment{name: rand_str()}
  end

  def currency_factory() do
    %Currency{code: "ETH"}
  end

  def ico_currency_factory() do
    %IcoCurrency{
      ico_id: 1,
      currency_id: 1,
      amount: 1000
    }
  end

  def infrastructure_factory() do
    %Infrastructure{
      code: "ETH"
    }
  end

  def project_eth_address_factory() do
    %ProjectEthAddress{
      address: "0x" <> (:crypto.strong_rand_bytes(16) |> Base.encode16()),
      source: "",
      comments: ""
    }
  end

  def project_btc_address_factory() do
    %ProjectBtcAddress{
      address: :crypto.strong_rand_bytes(16) |> Base.encode16(),
      source: "",
      comments: ""
    }
  end

  def exchange_address_factory() do
    %ExchangeAddress{
      address: "0x123",
      name: "Binance"
    }
  end

  def user_settings_factory() do
    %UserSettings{
      settings: %{
        signal_notify_telegram: false,
        signal_notify_email: false,
        newsletter_subscription: "OFF"
      }
    }
  end

  def user_trigger_factory() do
    %UserTrigger{
      user: build(:user),
      trigger: %{
        title: "Generic title"
      }
    }
  end

  def signals_historical_activity_factory() do
    %HistoricalActivity{
      user_trigger: %{}
    }
  end

  def watchlist_factory() do
    %UserList{name: "Generic User List name", color: :red, user: build(:user)}
  end

  def product_api_factory() do
    %Product{id: 1, name: "Neuro by Santiment"}
  end

  def product_sanbase_factory() do
    %Product{id: 2, name: "Sanabse by Santiment"}
  end

  def product_sheets_factory() do
    %Product{id: 3, name: "Sheets by Santiment"}
  end

  def product_graphs_factory() do
    %Product{id: 4, name: "Graphs by Santiment"}
  end

  def product_exchange_wallets_factory() do
    %Product{id: 5, name: "Exchange Wallets by Santiment"}
  end

  def plan_free_factory() do
    %Plan{
      id: 1,
      name: "FREE",
      amount: 0,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_essential_factory() do
    %Plan{
      id: 2,
      name: "ESSENTIAL",
      amount: 15_900,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_pro_factory() do
    %Plan{
      id: 3,
      name: "PRO",
      amount: 35_900,
      currency: "USD",
      interval: "month",
      stripe_id: plan_stripe_id()
    }
  end

  def plan_premium_factory() do
    %Plan{
      id: 4,
      name: "PREMIUM",
      amount: 75_900,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_custom_factory() do
    %Plan{
      id: 5,
      name: "CUSTOM",
      amount: 0,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_essential_yearly_factory() do
    %Plan{
      id: 6,
      name: "ESSENTIAL",
      amount: 128_520,
      currency: "USD",
      interval: "year"
    }
  end

  def plan_pro_yearly_factory() do
    %Plan{
      id: 7,
      name: "PRO",
      amount: 387_720,
      currency: "USD",
      interval: "year"
    }
  end

  def plan_premium_yearly_factory() do
    %Plan{
      id: 8,
      name: "PREMIUM",
      amount: 819_720,
      currency: "USD",
      interval: "year"
    }
  end

  def plan_custom_yearly_factory() do
    %Plan{
      id: 9,
      name: "CUSTOM",
      amount: 0,
      currency: "USD",
      interval: "year"
    }
  end

  def plan_free_sanbase_factory() do
    %Plan{
      id: 11,
      name: "FREE",
      amount: 0,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_basic_sanbase_factory() do
    %Plan{
      id: 12,
      name: "BASIC",
      amount: 1100,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_pro_sanbase_factory() do
    %Plan{
      id: 13,
      name: "PRO",
      amount: 5100,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_free_sheets_factory() do
    %Plan{
      id: 21,
      name: "FREE",
      amount: 0,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_basic_sheets_factory() do
    %Plan{
      id: 22,
      name: "BASIC",
      amount: 8900,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_pro_sheets_factory() do
    %Plan{
      id: 23,
      name: "PRO",
      amount: 18_900,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_enterprise_sheets_factory() do
    %Plan{
      id: 24,
      name: "ENTERPRISE",
      amount: 0,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_pro_graphs_factory() do
    %Plan{
      id: 42,
      name: "PRO",
      amount: 14000,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_exchange_wallets_extension_factory() do
    %Plan{
      id: 51,
      name: "EXTENSION",
      amount: 0,
      currency: "USD",
      interval: "month"
    }
  end

  def subscription_essential_factory() do
    %Subscription{
      stripe_id: rand_str(),
      plan_id: 2,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_pro_factory() do
    %Subscription{
      stripe_id: rand_str(),
      plan_id: 3,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_premium_factory() do
    %Subscription{
      stripe_id: rand_str(),
      plan_id: 4,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_basic_sanbase_factory() do
    %Subscription{
      plan_id: 12,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_pro_sanbase_factory() do
    %Subscription{
      plan_id: 13,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_basic_sheets_factory() do
    %Subscription{
      plan_id: 22,
      current_period_end: Timex.shift(Timex.now(), days: 1)
    }
  end

  def subscription_pro_sheets_factory() do
    %Subscription{
      plan_id: 23,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_pro_enterprise_factory() do
    %Subscription{
      plan_id: 24,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_exchange_wallets_extension_factory() do
    %Subscription{
      plan_id: 51,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def timeline_event_factory() do
    %TimelineEvent{}
  end

  def ico_factory() do
    %Ico{
      project_id: 1
    }
  end

  def role_san_team_factory() do
    %Role{
      id: 1,
      name: "Santiment Team member"
    }
  end

  def role_san_clan_factory() do
    %Role{
      id: 2,
      name: "Santiment Clan member"
    }
  end

  def user_role_factory() do
    %UserRole{}
  end

  def sign_up_trial_factory do
    %SignUpTrial{
      sent_welcome_email: false,
      sent_first_education_email: false,
      sent_second_education_email: false,
      sent_trial_will_end_email: false,
      sent_cc_will_be_charged: false,
      sent_trial_finished_without_cc: false
    }
  end

  def exchange_market_pair_mappings_factory do
    %Sanbase.Exchanges.MarketPairMapping{}
  end

  def rand_str(length \\ 10) do
    :crypto.strong_rand_bytes(length) |> Base.encode64() |> binary_part(0, length)
  end

  def rand_hex_str(length \\ 10) do
    :crypto.strong_rand_bytes(length) |> Base.hex_encode32(case: :lower) |> binary_part(0, length)
  end

  defp plan_stripe_id do
    {:ok, plan} = Sanbase.StripeApiTestReponse.create_plan_resp()
    plan.id
  end
end

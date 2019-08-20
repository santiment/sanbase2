defmodule Sanbase.Factory do
  use ExMachina.Ecto, repo: Sanbase.Repo

  alias Sanbase.Tag
  alias Sanbase.UserList
  alias Sanbase.Auth.{User, UserSettings}
  alias Sanbase.Insight.{Post, Poll}

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
      username: User.insights_fallback_username(),
      email: User.insights_fallback_email()
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

  def poll_factory() do
    %Poll{
      start_at: DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC"),
      end_at: DateTime.from_naive!(~N[2030-05-13 00:00:00], "Etc/UTC")
    }
  end

  def post_factory() do
    %Post{
      user: build(:user),
      poll: build(:poll),
      title: "Awesome analysis",
      link: "http://example.com",
      text: "Text of the post",
      state: Post.awaiting_approval_state(),
      tags: [build(:tag), build(:tag)]
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

  def random_erc20_project_factory() do
    %Project{
      name: rand_str(),
      ticker: rand_str(4),
      coinmarketcap_id: rand_str(),
      token_decimals: 18,
      total_supply: :rand.uniform(50_000_000) + 10_000_000,
      github_organizations: [build(:github_organization)],
      infrastructure:
        Sanbase.Repo.get_by(Infrastructure, code: "ETH") || build(:infrastructure, %{code: "ETH"}),
      eth_addresses: [build(:project_eth_address)],
      main_contract_address: "0x" <> rand_hex_str()
    }
  end

  def project_factory() do
    %Project{
      name: "Santiment",
      ticker: "SAN",
      coinmarketcap_id: "santiment",
      token_decimals: 18,
      total_supply: 83_000_000,
      github_organizations: [build(:github_organization)],
      infrastructure: nil,
      eth_addresses: [build(:project_eth_address)]
    }
  end

  def random_project_factory() do
    %Project{
      name: rand_str(),
      ticker: rand_hex_str() |> String.upcase(),
      coinmarketcap_id: rand_str(),
      token_decimals: 18,
      total_supply: :rand.uniform(50_000_000) + 10_000_000,
      github_organizations: [build(:github_organization)],
      infrastructure: nil,
      eth_addresses: [build(:project_eth_address)]
    }
  end

  def github_organization_factory() do
    %Project.GithubOrganization{
      organization: rand_str()
    }
  end

  def latest_cmc_data_factory() do
    %LatestCoinmarketcapData{
      coinmarketcap_id: "santiment",
      rank: 100,
      price_usd: 2,
      price_btc: 0.0001 |> Decimal.from_float(),
      volume_usd: 100_000,
      update_time: Timex.now()
    }
  end

  def market_segment_factory() do
    %MarketSegment{name: "currency"}
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
      amount: 15900,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_pro_factory() do
    %Plan{
      id: 3,
      name: "PRO",
      amount: 35900,
      currency: "USD",
      interval: "month",
      stripe_id: plan_stripe_id()
    }
  end

  def plan_premium_factory() do
    %Plan{
      id: 4,
      name: "PREMIUM",
      amount: 75900,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_enterprise_factory() do
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

  def plan_enterprise_yearly_factory() do
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

  def plan_enterprise_sanbase_factory() do
    %Plan{
      id: 14,
      name: "ENTERPRISE",
      amount: 0,
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
      amount: 18900,
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

  def subscription_essential_factory() do
    %Subscription{
      stripe_id: rand_str(),
      plan_id: 2,
      current_period_end: Timex.shift(Timex.now(), days: 1)
    }
  end

  def subscription_pro_factory() do
    %Subscription{
      stripe_id: rand_str(),
      plan_id: 3,
      current_period_end: Timex.shift(Timex.now(), days: 1)
    }
  end

  def subscription_premium_factory() do
    %Subscription{
      stripe_id: rand_str(),
      plan_id: 4,
      current_period_end: Timex.shift(Timex.now(), days: 1)
    }
  end

  def subscription_basic_sanbase_factory() do
    %Subscription{
      plan_id: 12,
      current_period_end: Timex.shift(Timex.now(), days: 1)
    }
  end

  def subscription_pro_sanbase_factory() do
    %Subscription{
      plan_id: 13,
      current_period_end: Timex.shift(Timex.now(), days: 1)
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
      current_period_end: Timex.shift(Timex.now(), days: 1)
    }
  end

  def subscription_pro_enterprise_factory() do
    %Subscription{
      plan_id: 24,
      current_period_end: Timex.shift(Timex.now(), days: 1)
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

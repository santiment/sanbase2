defmodule Sanbase.Factory do
  use ExMachina.Ecto, repo: Sanbase.Repo

  alias Sanbase.Tag
  alias Sanbase.UserList
  alias Sanbase.Accounts.{User, UserSettings, Role, UserRole, EmailLoginAttempt}
  alias Sanbase.Insight.Post
  alias Sanbase.Comment
  alias Sanbase.{Project, ProjectEthAddress, ProjectBtcAddress}

  alias Sanbase.Model.{
    Infrastructure,
    MarketSegment,
    LatestCoinmarketcapData,
    Currency,
    Ico,
    IcoCurrency
  }

  alias Sanbase.Alert.{UserTrigger, HistoricalActivity}
  alias Sanbase.Billing.{Product, Plan, Subscription}
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Chart
  alias Sanbase.TableConfiguration
  alias Sanbase.Email.NewsletterToken
  alias Sanbase.Report
  alias Sanbase.BlockchainAddress
  alias Sanbase.SheetsTemplate
  alias Sanbase.Webinar
  alias Sanbase.Accounts.Interaction

  def intercation_factory do
    %Interaction{}
  end

  def user_factory() do
    %User{
      username: :crypto.strong_rand_bytes(16) |> Base.encode16(),
      email: (:crypto.strong_rand_bytes(16) |> Base.encode16()) <> "@santiment.net",
      salt: User.generate_salt(),
      privacy_policy_accepted: true,
      san_balance: Decimal.new(0),
      san_balance_updated_at: Timex.now()
    }
  end

  def market_factory() do
    %Sanbase.Market{
      base_asset: "BTC",
      quote_asset: "USD",
      exchange: "Binance",
      source: "cryptocompare"
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

  def blockchain_address_factory() do
    %BlockchainAddress{
      address: "0x" <> rand_hex_str(38),
      infrastructure:
        Sanbase.Repo.get_by(Infrastructure, code: "ETH") || build(:infrastructure, %{code: "ETH"})
    }
  end

  def post_factory() do
    metric = Sanbase.Metric.available_metrics() |> Enum.random()

    %Post{
      user: build(:user),
      title: "Awesome analysis",
      text: "Text of the post",
      is_pulse: false,
      is_paywall_required: false,
      tags: [build(:tag), build(:tag)],
      metrics: [
        Sanbase.Repo.get_by(Sanbase.Metric.MetricPostgresData, name: metric) ||
          build(:metric_postgres, %{name: metric})
      ]
    }
  end

  def published_post_factory() do
    metric = Sanbase.Metric.available_metrics() |> Enum.random()

    %Post{
      state: Post.approved_state(),
      ready_state: Post.published(),
      user: build(:user),
      title: "Awesome analysis",
      text: "Text of the post",
      is_pulse: false,
      is_paywall_required: false,
      tags: [build(:tag), build(:tag)],
      metrics: [
        Sanbase.Repo.get_by(Sanbase.Metric.MetricPostgresData, name: metric) ||
          build(:metric_postgres, %{name: metric})
      ],
      published_at: DateTime.utc_now()
    }
  end

  def metric_postgres_factory() do
    %Sanbase.Metric.MetricPostgresData{
      name: Sanbase.Metric.available_metrics() |> Enum.random()
    }
  end

  def chart_configuration_factory() do
    %Chart.Configuration{
      title: "chart configuration",
      project: insert(:random_project),
      user: build(:user)
    }
  end

  def dashboard_factory() do
    %Sanbase.Dashboard.Schema{
      name: "My Dashboard",
      user: build(:user)
    }
  end

  def table_configuration_factory() do
    %TableConfiguration{
      title: "table configuration",
      user: build(:user)
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
      text: "Text of the post",
      state: Post.awaiting_approval_state()
    }
  end

  def popular_search_term_factory() do
    %Sanbase.SocialData.PopularSearchTerm{
      title: "Some Title",
      datetime: Timex.now(),
      selector_type: "text",
      search_term: rand_str(3) <> " OR " <> rand_str(6),
      options: %{interval: "1h", width: "60d"}
    }
  end

  def active_widget_factory() do
    %Sanbase.Widget.ActiveWidget{
      title: "Some Title",
      description: "Some Description",
      image_link: "https://image.png",
      video_link: "https://youtube.com/video_id",
      is_active: true
    }
  end

  def random_erc20_project_factory(attrs) do
    slug = Map.get(attrs, :slug, rand_str())
    coinmarketcap_id = Map.get(attrs, :coinmarketcap_id, slug)

    %Project{
      name: rand_str(),
      ticker: rand_str(4),
      slug: slug,
      coinmarketcap_id: coinmarketcap_id,
      is_hidden: false,
      source_slug_mappings: [
        build(:source_slug_mapping, %{source: "coinmarketcap", slug: slug})
      ],
      token_decimals: 18,
      total_supply: :rand.uniform(50_000_000) + 10_000_000,
      twitter_link: "https://twitter.com/#{rand_hex_str()}",
      telegram_link: "https://telegram.com/#{rand_hex_str()}",
      github_organizations: [build(:github_organization)],
      contract_addresses: [build(:contract_address)],
      market_segments: [build(:market_segment)],
      infrastructure:
        Sanbase.Repo.get_by(Infrastructure, code: "ETH") || build(:infrastructure, %{code: "ETH"}),
      eth_addresses: [build(:project_eth_address)]
    }
    |> merge_attributes(attrs)
  end

  def project_factory(attrs) do
    slug = Map.get(attrs, :slug, "santiment")
    coinmarketcap_id = Map.get(attrs, :coinmarketcap_id, slug)

    %Project{
      name: "Santiment",
      ticker: "SAN",
      slug: slug,
      coinmarketcap_id: coinmarketcap_id,
      is_hidden: false,
      source_slug_mappings: [
        build(:source_slug_mapping, %{source: "coinmarketcap", slug: slug})
      ],
      token_decimals: 18,
      total_supply: 83_000_000,
      twitter_link: "https://twitter.com/santimentfeed",
      discord_link: "https://santiment.net/discord",
      github_organizations: [build(:github_organization)],
      contract_addresses: [build(:contract_address)],
      market_segments: [build(:market_segment)],
      infrastructure: nil,
      eth_addresses: [build(:project_eth_address)]
    }
    |> merge_attributes(attrs)
  end

  def random_project_factory(attrs) do
    slug = Map.get(attrs, :slug, rand_str())
    ticker = Map.get(attrs, :ticker, rand_str(4) |> String.upcase())
    coinmarketcap_id = Map.get(attrs, :coinmarketcap_id, slug)

    %Project{
      name: rand_str(),
      ticker: ticker,
      slug: slug,
      coinmarketcap_id: coinmarketcap_id,
      is_hidden: false,
      source_slug_mappings: [
        build(:source_slug_mapping, %{source: "coinmarketcap", slug: slug})
      ],
      token_decimals: 18,
      total_supply: :rand.uniform(50_000_000) + 10_000_000,
      twitter_link: "https://twitter.com/#{rand_hex_str()}",
      discord_link: "https://discord.gg/#{rand_hex_str()}",
      github_organizations: [build(:github_organization)],
      contract_addresses: [build(:contract_address)],
      market_segments: [build(:market_segment)],
      infrastructure: nil,
      eth_addresses: [build(:project_eth_address)]
    }
    |> merge_attributes(attrs)
  end

  def contract_address_factory() do
    %Project.ContractAddress{
      address: "0x" <> rand_hex_str(16),
      decimals: 18,
      label: rand_str(6),
      description: "Some description."
    }
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
    %MarketSegment{name: rand_str(), type: rand_str()}
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

  def user_settings_factory() do
    %UserSettings{
      settings: %{
        alert_notify_telegram: false,
        alert_notify_email: false
      }
    }
  end

  def user_trigger_factory(attrs) do
    is_public = Map.get(attrs, :is_public, false)
    attrs = Map.delete(attrs, :is_public)

    %UserTrigger{
      user: build(:user),
      trigger: %{
        title: "Generic title",
        is_public: is_public,
        settings: trigger_settings()
      }
    }
    |> merge_attributes(attrs)
  end

  defp trigger_settings() do
    %{
      "type" => "metric_signal",
      "metric" => "daily_active_addresses",
      "target" => %{"slug" => "santiment"},
      "channel" => "telegram",
      "time_window" => "1d",
      "operation" => %{"percent_up" => 300.0}
    }
  end

  def alerts_historical_activity_factory() do
    %HistoricalActivity{
      user_trigger: %{}
    }
  end

  def watchlist_factory() do
    %UserList{name: "Generic User List name", color: :red, user: build(:user), is_screener: false}
  end

  def screener_factory() do
    %UserList{name: "Generic User List name", color: :red, user: build(:user), is_screener: true}
  end

  def product_api_factory() do
    %Product{id: 1, name: "Neuro by Santiment", code: "SANAPI"}
  end

  def product_sanbase_factory() do
    %Product{id: 2, name: "Sanbase by Santiment", code: "SANBASE"}
  end

  def product_sandata_factory() do
    %Product{id: 4, name: "Sandata by Santiment", code: "SANDATA"}
  end

  def product_exchange_wallets_factory() do
    %Product{id: 5, name: "Exchange Wallets by Santiment", code: "SAN_EXCHANGE_WALLETS"}
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
      id: 205,
      name: "BASIC",
      amount: 2500,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_pro_sanbase_factory() do
    %Plan{
      id: 201,
      name: "PRO",
      amount: 4900,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_pro_sanbase_yearly_factory() do
    %Plan{
      id: 202,
      name: "PRO",
      amount: 52900,
      currency: "USD",
      interval: "year"
    }
  end

  def plan_pro_plus_sanbase_factory() do
    %Plan{
      id: 203,
      name: "PRO_PLUS",
      amount: 24900,
      currency: "USD",
      interval: "month"
    }
  end

  def plan_pro_sandata_factory() do
    %Plan{
      id: 42,
      name: "PRO",
      amount: 14_000,
      currency: "USD",
      interval: "month"
    }
  end

  def subscription_factory() do
    %Subscription{
      stripe_id: rand_str(),
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
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

  def subscription_custom_factory() do
    %Subscription{
      stripe_id: rand_str(),
      plan_id: 5,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_basic_sanbase_factory() do
    %Subscription{
      plan_id: 205,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_pro_sanbase_factory() do
    %Subscription{
      plan_id: 201,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_pro_plus_sanbase_factory() do
    %Subscription{
      plan_id: 203,
      current_period_end: Timex.shift(Timex.now(), days: 1),
      status: "active"
    }
  end

  def subscription_pro_custom_factory() do
    %Subscription{
      plan_id: 24,
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
      name: "Santiment Team Member"
    }
  end

  def role_san_family_factory() do
    %Role{
      id: 2,
      name: "Santiment Family Member"
    }
  end

  def role_san_moderator_factory() do
    %Role{
      id: 3,
      name: "Santiment Moderator"
    }
  end

  def user_role_factory() do
    %UserRole{}
  end

  def exchange_market_pair_mappings_factory do
    %Sanbase.Exchanges.MarketPairMapping{}
  end

  def newsletter_token_factory do
    %NewsletterToken{
      token: :crypto.strong_rand_bytes(64) |> Base.encode64(),
      email: (:crypto.strong_rand_bytes(16) |> Base.encode16()) <> "@santiment.net",
      email_token_generated_at: DateTime.utc_now()
    }
  end

  def report_factory do
    %Report{
      url: "https://example.com/#{rand_hex_str()}_report.pdf",
      name: "Alpha Report"
    }
  end

  def sheets_template_factory do
    %SheetsTemplate{
      url: "https://example.com/#{rand_hex_str()}",
      name: "Top Transactions"
    }
  end

  def webinar_factory do
    %Webinar{
      url: "https://example.com/#{rand_hex_str()}",
      title: "Webinar title",
      description: "Webinar description",
      image_url: "https://example.com/#{rand_hex_str()}",
      start_time: Timex.shift(Timex.now(), days: 1),
      end_time: Timex.shift(Timex.now(), days: 2)
    }
  end

  def short_url_factory do
    %Sanbase.ShortUrl{
      short_url: rand_str(),
      full_url: "https://santiment.net"
    }
  end

  def uniswap_staking_factory do
    %Sanbase.Accounts.User.UniswapStaking{
      san_staked: 3000
    }
  end

  def email_login_attempt_factory() do
    rand_octet = fn -> :rand.uniform(255) end

    %EmailLoginAttempt{
      user: build(:user),
      ip_address: "#{rand_octet.()}.#{rand_octet.()}.#{rand_octet.()}.#{rand_octet.()}"
    }
  end

  def vote_factory do
    %Sanbase.Vote{}
  end

  def rand_str(length \\ 10) do
    :crypto.strong_rand_bytes(length) |> Base.encode64() |> binary_part(0, length)
  end

  def rand_hex_str(length \\ 10) do
    :crypto.strong_rand_bytes(length) |> Base.hex_encode32(case: :lower) |> binary_part(0, length)
  end

  defp plan_stripe_id do
    {:ok, plan} = Sanbase.StripeApiTestResponse.create_plan_resp()
    plan.id
  end
end

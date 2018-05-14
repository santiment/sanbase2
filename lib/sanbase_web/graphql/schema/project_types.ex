defmodule SanbaseWeb.Graphql.ProjectTypes do
  use Absinthe.Schema.Notation
  use Absinthe.Ecto, repo: Sanbase.Repo

  import Absinthe.Resolution.Helpers
  import SanbaseWeb.Graphql.Helpers.Cache, only: [cache_resolve: 1, cache_resolve_dataloader: 1]

  alias SanbaseWeb.Graphql.Resolvers.{
    ProjectResolver,
    ProjectBalanceResolver,
    IcoResolver,
    TwitterResolver,
    EtherbiResolver
  }

  alias SanbaseWeb.Graphql.SanbaseRepo

  # Includes all available fields
  @desc ~s"""
  A type fully describing a project.
  """
  object :project do
    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:ticker, :string)
    field(:logo_url, :string)
    field(:website_link, :string)
    field(:email, :string)
    field(:btt_link, :string)
    field(:facebook_link, :string)
    field(:github_link, :string)
    field(:reddit_link, :string)
    field(:twitter_link, :string)
    field(:whitepaper_link, :string)
    field(:blog_link, :string)
    field(:slack_link, :string)
    field(:linkedin_link, :string)
    field(:telegram_link, :string)
    field(:token_address, :string)
    field(:team_token_wallet, :string)
    field(:description, :string)
    field(:token_decimals, :integer)
    field(:main_contract_address, :string)
    field(:eth_addresses, list_of(:eth_address), resolve: dataloader(SanbaseRepo))

    field :related_posts, list_of(:post) do
      resolve(&ProjectResolver.related_posts/3)
    end

    field :market_segment, :string do
      resolve(&ProjectResolver.market_segment/3)
    end

    field :infrastructure, :string do
      resolve(&ProjectResolver.infrastructure/3)
    end

    field(:project_transparency, :boolean)

    field :project_transparency_status, :string do
      resolve(&ProjectResolver.project_transparency_status/3)
    end

    field(:project_transparency_description, :string)

    field :eth_balance, :decimal do
      cache_resolve_dataloader(&ProjectBalanceResolver.eth_balance/3)
    end

    field :btc_balance, :decimal do
      cache_resolve_dataloader(&ProjectBalanceResolver.btc_balance/3)
    end

    field :usd_balance, :decimal do
      cache_resolve_dataloader(&ProjectBalanceResolver.usd_balance/3)
    end

    field :funds_raised_icos, list_of(:currency_amount) do
      cache_resolve(&ProjectResolver.funds_raised_icos/3)
    end

    field :roi_usd, :decimal do
      cache_resolve(&ProjectResolver.roi_usd/3)
    end

    field(:coinmarketcap_id, :string)

    field :symbol, :string do
      resolve(&ProjectResolver.symbol/3)
    end

    field :rank, :integer do
      resolve(&ProjectResolver.rank/3)
    end

    field :price_usd, :decimal do
      resolve(&ProjectResolver.price_usd/3)
    end

    field :price_btc, :decimal do
      resolve(&ProjectResolver.price_btc/3)
    end

    field :volume_usd, :decimal do
      resolve(&ProjectResolver.volume_usd/3)
    end

    field :volume_change_24h, :float, name: "volume_change24h" do
      resolve(&ProjectResolver.volume_change_24h/3)
    end

    field :average_dev_activity, :float do
      description("Average dev activity for the last 30 days")
      resolve(&ProjectResolver.average_dev_activity/3)
    end

    field :twitter_data, :twitter_data do
      resolve(&TwitterResolver.twitter_data/3)
    end

    field :marketcap_usd, :decimal do
      resolve(&ProjectResolver.marketcap_usd/3)
    end

    field :available_supply, :decimal do
      resolve(&ProjectResolver.available_supply/3)
    end

    field :total_supply, :decimal do
      resolve(&ProjectResolver.total_supply/3)
    end

    field :percent_change_1h, :decimal, name: "percent_change1h" do
      resolve(&ProjectResolver.percent_change_1h/3)
    end

    field :percent_change_24h, :decimal, name: "percent_change24h" do
      resolve(&ProjectResolver.percent_change_24h/3)
    end

    field :percent_change_7d, :decimal, name: "percent_change7d" do
      resolve(&ProjectResolver.percent_change_7d/3)
    end

    field :funds_raised_usd_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_usd_ico_end_price/3)
    end

    field :funds_raised_eth_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_eth_ico_end_price/3)
    end

    field :funds_raised_btc_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_btc_ico_end_price/3)
    end

    field :initial_ico, :ico do
      cache_resolve(&ProjectResolver.initial_ico/3)
    end

    field(:icos, list_of(:ico), resolve: assoc(:icos))

    field :ico_price, :float do
      cache_resolve(&ProjectResolver.ico_price/3)
    end

    field :signals, list_of(:signal) do
      cache_resolve_dataloader(&ProjectResolver.signals/3)
    end

    field :price_to_book_ratio, :decimal do
      cache_resolve_dataloader(&ProjectResolver.price_to_book_ratio/3)
    end

    field :eth_spent, :float do
      arg(:days, :integer, default_value: 30)

      resolve(&ProjectResolver.eth_spent/3)
    end

    field :eth_spent_over_time, list_of(:eth_spent_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      resolve(&ProjectResolver.eth_spent_over_time/3)
    end

    field :eth_top_transactions, list_of(:wallet_transaction) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:transaction_type, :transaction_type, default_value: :all)
      arg(:limit, :integer, default_value: 10)

      resolve(&ProjectResolver.eth_top_transactions/3)
    end

    @desc "Average daily active addresses for a ticker and given time period"
    field :average_daily_active_addresses, :integer do
      arg(:from, :datetime)
      arg(:to, :datetime)

      resolve(&EtherbiResolver.average_daily_active_addresses/3)
    end
  end

  object :eth_address do
    field(:address, non_null(:string))

    field :balance, :decimal do
      resolve(&ProjectBalanceResolver.eth_address_balance/3)
    end
  end

  object :ico do
    field(:id, non_null(:id))
    field(:start_date, :ecto_date)
    field(:end_date, :ecto_date)
    field(:token_usd_ico_price, :decimal)
    field(:token_eth_ico_price, :decimal)
    field(:token_btc_ico_price, :decimal)
    field(:tokens_issued_at_ico, :decimal)
    field(:tokens_sold_at_ico, :decimal)

    field :funds_raised_usd_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_usd_ico_end_price/3)
    end

    field :funds_raised_eth_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_eth_ico_end_price/3)
    end

    field :funds_raised_btc_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_btc_ico_end_price/3)
    end

    field(:minimal_cap_amount, :decimal)
    field(:maximal_cap_amount, :decimal)
    field(:contract_block_number, :integer)
    field(:contract_abi, :string)
    field(:comments, :string)

    field :cap_currency, :string do
      resolve(&IcoResolver.cap_currency/3)
    end

    field :funds_raised, list_of(:currency_amount) do
      resolve(&IcoResolver.funds_raised/3)
    end
  end

  object :ico_with_eth_contract_info do
    field(:id, non_null(:id))
    field(:start_date, :ecto_date)
    field(:end_date, :ecto_date)
    field(:main_contract_address, :string)
    field(:contract_block_number, :integer)
    field(:contract_abi, :string)
  end

  object :currency_amount do
    field(:currency_code, :string)
    field(:amount, :float)
  end

  object :signal do
    field(:name, non_null(:string))
    field(:description, non_null(:string))
  end

  object :eth_spent_data do
    field(:datetime, non_null(:datetime))
    field(:eth_spent, :float)
  end
end

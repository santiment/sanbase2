defmodule SanbaseWeb.Graphql.ProjectTypes do
  use Absinthe.Schema.Notation
  use Absinthe.Ecto, repo: Sanbase.Repo

  import_types Absinthe.Type.Custom
  import_types SanbaseWeb.Graphql.CustomTypes

  alias SanbaseWeb.Graphql.ProjectResolver

  object :project do
    field :id, non_null(:id)
    field :name, non_null(:string)
    field :ticker, :string
    field :logo_url, :string
    field :website_link, :string
    field :btt_link, :string
    field :facebook_link, :string
    field :github_link, :string
    field :reddit_link, :string
    field :twitter_link, :string
    field :whitepaper_link, :string
    field :blog_link, :string
    field :slack_link, :string
    field :linkedin_link, :string
    field :telegram_link, :string
    field :token_address, :string
    field :team_token_wallet, :string
    field :market_cap_usd, :decimal
    field :project_transparency, :boolean
    field :project_transparency_status, :string
    field :project_transparency_description, :string
    field :latest_coinmarketcap_data, :latest_coinmarketcap_data, resolve: assoc(:latest_coinmarketcap_data)

    field :eth_balance, :decimal do
      resolve &ProjectResolver.eth_balance/3
    end
    field :btc_balance, :decimal do
      resolve &ProjectResolver.btc_balance/3
    end
    # If there is no data for any currency for any ico, then fallback to one of Ico.funds_raised_usd, Ico.funds_raised_btc, Ico.funds_raised_eth (in that order)
    field :funds_raised_icos, list_of(:currency_amount) do
      resolve &ProjectResolver.funds_raised_icos/3
    end
  end

  object :latest_coinmarketcap_data do
    field :id, non_null(:id)
    field :coinmarketcap_id, non_null(:string)
    field :name, :string
    field :market_cap_usd, :decimal
    field :price_usd, :decimal
    field :symbol, :string
    field :update_time, :ecto_datetime
  end

  object :currency_amount do # TODO: change name in ico_currencies too value->amount
    field :currency_code, :string
    field :amount, :decimal
  end
end

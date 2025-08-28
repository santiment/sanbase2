defmodule Sanbase.MCP.DataCatalog.AvailableMetrics do
  def list() do
    list =
      financial_metrics() ++
        development_activity_metrics() ++
        social_metrics() ++
        on_chain_metrics()

    List.flatten(list)
  end

  def financial_metrics() do
    [
      %{
        name: "price_usd",
        description: "Price in USD for cryptocurrencies",
        unit: "USD",
        supports_many_slugs: true
      },
      %{
        name: "marketcap_usd",
        description: "Total market capitalization in USD",
        unit: "USD",
        supports_many_slugs: true
      },
      %{
        name: "volume_usd",
        description: "Trading volume in USD",
        unit: "USD",
        supports_many_slugs: true
      },
      %{
        name: "price_btc",
        description: "Asset price denominated in BTC",
        unit: "BTC",
        supports_many_slugs: true
      },
      %{
        name: "price_volatility_1d",
        description: "Realized price volatility over 1 day",
        unit: "percent",
        supports_many_slugs: true
      },
      %{
        name: "fully_diluted_valuation_usd",
        description: "Fully diluted valuation in USD",
        unit: "USD",
        supports_many_slugs: true
      }
    ]
  end

  def development_activity_metrics() do
    [
      %{
        name: "dev_activity_1d",
        description:
          "Development activity events on tracked repositories (commits, PRs, issues, etc.)",
        unit: "count",
        supports_many_slugs: true
      },
      %{
        name: "dev_activity_contributors_count_7d",
        description: """
        Number of unique developers contributing across tracked repositories of the asset,
        computed at 7 day sliding windows. Data points are produced for each day and each
        point is computed using the data from the previous 7 days.
        """,
        unit: "count",
        supports_many_slugs: true
      }
    ]
  end

  def social_metrics() do
    [
      %{
        name: "social_volume_total",
        description: "Total social media mentions and discussions",
        unit: "count"
      },
      %{
        name: "social_dominance_total",
        description: "Share of total crypto social mentions attributed to the asset",
        unit: "percent"
      },
      %{
        name: "sentiment_weighted_total",
        description: "Overall weighted social sentiment score",
        unit: "score"
      },
      for source <- [:twitter, :telegram, :reddit] do
        [
          %{
            name: "sentiment_weighted_#{source}",
            description:
              "Weighted social sentiment score computed on the text messages in #{source}",
            unit: "score"
          },
          %{
            name: "social_volume_#{source}",
            description: "Social media mentions in #{source}",
            unit: "count"
          },
          %{
            name: "social_dominance_#{source}",
            description: "Share of crypto social mentions attributed to the asset in #{source}",
            unit: "percent"
          }
        ]
      end,
      %{
        name: "twitter_followers",
        description: "Number of followers on the project's official Twitter/X account",
        unit: "count"
      }
    ]
    |> List.flatten()
  end

  def on_chain_metrics() do
    [
      %{
        name: "daily_active_addresses",
        description: "Daily active addresses",
        unit: "count",
        supports_many_slugs: true
      },
      %{
        name: "transactions_count",
        description: "Number of on-chain transactions",
        unit: "count",
        supports_many_slugs: true
      },
      %{
        name: "transaction_volume",
        description: "On-chain transaction volume in number of coins/tokens",
        unit: "count",
        supports_many_slugs: true
      },
      %{
        name: "transaction_volume_usd",
        description: "On-chain transaction volume in USD",
        unit: "USD",
        supports_many_slugs: true
      },
      %{
        name: "network_growth",
        description: "New addresses that made their first on-chain transaction",
        unit: "count",
        supports_many_slugs: true
      },
      %{
        name: "mvrv_usd",
        description: "Market Value to Realized Value ratio (USD terms)",
        unit: "ratio",
        supports_many_slugs: true
      },
      %{
        name: "supply_on_exchanges",
        description: "Amount of tokens held on exchange addresses",
        unit: "tokens",
        supports_many_slugs: true
      },
      %{
        name: "exchange_inflow_usd",
        description: "USD value of tokens deposited to exchange addresses",
        unit: "USD",
        supports_many_slugs: true
      },
      %{
        name: "exchange_outflow_usd",
        description: "USD value of tokens withdrawn from exchange addresses",
        unit: "USD",
        supports_many_slugs: true
      }
    ]
  end
end

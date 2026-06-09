defmodule Sanbase.MCP.ChartMetricCatalog do
  @moduledoc """
  Curated whitelist of metrics the chart widget can plot.

  Acts as both:
  - validation source for the `primary` / `overlay` tool args (LLM must pick from here)
  - render hints (style/pane/color/unit) baked into the structured response so the
    widget stays a dumb renderer
  """

  # `name` — Sanbase API metric id (matches `metric_registry`)
  # `style` — rendering hint for the widget: `:line` / `:area` / `:histogram` / `:candles`
  # `default_pane` — `0` = main pane (with price), `1` = below
  # `color` — default hex (widget can override)
  # `unit` — short label for the y-axis (`"usd"`, `"percent"`, `""`)
  @entries [
    %{
      name: "price_usd",
      label: "Price USD",
      style: :candles,
      default_pane: 0,
      color: "#26a69a",
      unit: "usd",
      description: "OHLC price in USD"
    },

    # Social
    %{
      name: "social_volume_total",
      label: "Social volume",
      style: :histogram,
      default_pane: 1,
      color: "#4a90e2",
      unit: "",
      description: "Total number of mentions across all sources"
    },
    %{
      name: "social_dominance_total",
      label: "Social dominance",
      style: :line,
      default_pane: 1,
      color: "#5e72e4",
      unit: "percent",
      description: "Share of attention vs whole crypto market"
    },
    %{
      name: "sentiment_balance_total",
      label: "Sentiment balance",
      style: :line,
      default_pane: 1,
      color: "#9b59b6",
      unit: "",
      description: "Bullish minus bearish mentions"
    },
    %{
      name: "sentiment_weighted_total",
      label: "Sentiment weighted",
      style: :line,
      default_pane: 1,
      color: "#8e44ad",
      unit: "",
      description: "Sentiment weighted by mention volume"
    },

    # Network activity
    %{
      name: "daily_active_addresses",
      label: "Daily active addresses",
      style: :histogram,
      default_pane: 1,
      color: "#1abc9c",
      unit: "",
      description: "Unique addresses transacting per day"
    },
    %{
      name: "network_growth",
      label: "Network growth",
      style: :histogram,
      default_pane: 1,
      color: "#16a085",
      unit: "",
      description: "New unique addresses joining the network"
    },
    %{
      name: "transaction_volume_usd",
      label: "Transaction volume",
      style: :histogram,
      default_pane: 1,
      color: "#27ae60",
      unit: "usd",
      description: "On-chain transaction volume in USD"
    },
    %{
      name: "velocity",
      label: "Velocity",
      style: :line,
      default_pane: 1,
      color: "#2ecc71",
      unit: "",
      description: "Speed of money — circulation rate"
    },

    # On-chain ratios / valuation
    %{
      name: "mvrv_usd",
      label: "MVRV (USD)",
      style: :line,
      default_pane: 1,
      color: "#e67e22",
      unit: "",
      description: "Market Value to Realized Value — over/undervaluation signal"
    },
    %{
      name: "nvt",
      label: "NVT",
      style: :line,
      default_pane: 1,
      color: "#d35400",
      unit: "",
      description: "Network Value to Transactions — valuation vs throughput"
    },
    %{
      name: "realized_value_usd",
      label: "Realized value",
      style: :line,
      default_pane: 1,
      color: "#f39c12",
      unit: "usd",
      description: "Sum of all coins valued at last-moved price"
    },
    %{
      name: "mvrv_long_short_diff_usd",
      label: "MVRV long/short diff",
      style: :line,
      default_pane: 1,
      color: "#c0392b",
      unit: "",
      description: "Smart money divergence between long and short holders"
    },

    # Holders / whales
    %{
      name: "exchange_balance",
      label: "Exchange balance",
      style: :line,
      default_pane: 1,
      color: "#e74c3c",
      unit: "",
      description: "Net asset balance on centralized exchanges"
    },
    %{
      name: "whale_transaction_count_100k_usd_to_inf",
      label: "Whale tx count (>$100k)",
      style: :histogram,
      default_pane: 1,
      color: "#34495e",
      unit: "",
      description: "Number of on-chain transfers above $100,000"
    },
    %{
      name: "top_holders_held_supply_percent",
      label: "Top holders % supply",
      style: :line,
      default_pane: 1,
      color: "#7f8c8d",
      unit: "percent",
      description: "Share of supply held by top wallets (concentration)"
    },

    # Dev activity
    %{
      name: "dev_activity",
      label: "Dev activity",
      style: :histogram,
      default_pane: 1,
      color: "#3498db",
      unit: "",
      description: "Santiment dev score — github events excluding noise"
    },
    %{
      name: "github_activity",
      label: "Github activity",
      style: :histogram,
      default_pane: 1,
      color: "#2980b9",
      unit: "",
      description: "Raw github events count"
    },

    # Market basics (also valid as primary)
    %{
      name: "volume_usd",
      label: "Trading volume",
      style: :histogram,
      default_pane: 1,
      color: "#95a5a6",
      unit: "usd",
      description: "24h trading volume in USD"
    },
    %{
      name: "marketcap_usd",
      label: "Market cap",
      style: :line,
      default_pane: 0,
      color: "#2c3e50",
      unit: "usd",
      description: "Market capitalization in USD"
    },

    # Derivatives
    %{
      name: "funding_rate_perp",
      label: "Funding rate (perp)",
      style: :line,
      default_pane: 1,
      color: "#e91e63",
      unit: "percent",
      description: "Perpetual futures funding rate — leverage skew"
    }
  ]

  @entries_by_name Map.new(@entries, &{&1.name, &1})
  @names Enum.map(@entries, & &1.name)

  @doc "All catalog entries in declaration order."
  def entries, do: @entries

  @doc "All metric names (for enum validation)."
  def names, do: @names

  @doc "Look up a single entry by metric name."
  def fetch(name), do: Map.fetch(@entries_by_name, name)

  @doc "Look up; raise if missing (use only after validation)."
  def fetch!(name), do: Map.fetch!(@entries_by_name, name)

  @doc "Special primary value — OHLC price, handled outside of generic metric path."
  def price_primary, do: "price"

  @doc "Is the given primary value the special OHLC-price one?"
  def price_primary?(value), do: value in [nil, "", "price", "price_usd"]
end

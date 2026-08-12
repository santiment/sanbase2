defmodule Sanbase.Metric.Category.TaxonomyImporter do
  @moduledoc ~s"""
  Applies the metric taxonomy for the five API data packages to
  `metric_categories` / `metric_groups` / `metric_category_mappings`.

  Run it from an iex shell on stage or production - there is no `mix` there:

      # See what would change, write nothing. Start here, every time.
      Sanbase.Metric.Category.TaxonomyImporter.plan()

      # One package at a time
      Sanbase.Metric.Category.TaxonomyImporter.plan(["market"])

      # Write
      Sanbase.Metric.Category.TaxonomyImporter.apply!(["market"])
      Sanbase.Metric.Category.TaxonomyImporter.apply!()

      # Which specs exist
      Sanbase.Metric.Category.TaxonomyImporter.specs()

  Idempotent: a second run is a no-op. Safe to re-run after product edits a spec.

  The five taxonomies are **inlined below as module attributes**, so this file is
  self-contained: it can be pasted whole into `bin/sanbase remote` and used
  before it is deployed anywhere. That is what makes it testable on stage without
  a release. Once deployed it is an ordinary module and the paste is unnecessary.

  Changing the taxonomy means editing this file, which means code review - a
  package's contents are contractual, so that is the intent rather than a cost.
  Each `@taxonomy_*` attribute is one package, and the shape is:

      %{
        category: "Market",                      # metric_categories.name - the DB key
        groups: [
          %{name: "Pricing", metrics: [...]},    # order in this list is display_order
          %{name: "Regular Sentiment", metrics: [], rollup: true},
          %{name: "Positive Sentiment", metrics: [...], also: ["Regular Sentiment"]}
        ],
        rename_groups: %{"XRP" => "XRPL Chain"}, # keep an existing group's id
        delete_groups: ["Total sentiment"],      # dissolve, once its metrics are placed
        remove_from_groups: %{                   # per-row version, for a KEPT group
          "Top Holders" => ["whale_transaction_count_1m_usd_to_inf"]
        },
        moves: [%{metric: "nft_market_volume", to_category: "On-chain Labels", to_group: "NFT"}]
      }

  ## What it does, per spec

    1. Renames existing groups (`rename_groups`), so their ids, mappings and
       display_order survive a name change instead of being rebuilt.
    2. Creates missing groups in the spec's order, and renumbers `display_order`
       to match that order.
    3. Gives every metric named in a group a mapping row for (category, group).
       A group's `also` list adds a second row per metric - that is how a metric
       lives in both a narrow group and a roll-up (Positive Sentiment *and*
       Regular Sentiment). The schema allows it: the unique index is on
       `(metric, category_id, group_id)` with `nulls_distinct: false`.
    4. Deletes the metric's ungrouped (`group_id IS NULL`) row once it has at
       least one grouped row. Left in place it appears twice in
       `getOrderedMetricsV2` and once under "Ungrouped" in the admin filter.
    5. Renumbers mapping `display_order` densely inside each group.
    6. Empties and deletes the groups in `delete_groups` - but **refuses** if a
       metric in them is not placed somewhere by the spec, so dissolving an old
       group can never silently drop a metric out of the taxonomy. Removes the
       individual rows in `remove_from_groups`, under the same guard, for a group
       that is kept rather than dissolved.
    7. Moves the metrics in `moves` to another category. A move is a delete plus
       an insert, not a second membership: leaving the source row behind keeps
       the metric sellable through the source package.

  It never invents a metric. A name in a spec with no existing mapping row in
  that category is reported and skipped - see
  `docs/metric-taxonomy-open-questions.md`.

  ## After applying

  Package contents are frozen in `bundle_package_snapshots`, so regrouping does
  not change what existing customers get until a new snapshot is published.
  Review the diff first:

      Sanbase.Billing.Plan.Bundle.PackageSnapshot.pending_changes()
  """

  import Ecto.Query

  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Category.MetricGroup
  alias Sanbase.Repo

  # Market data package taxonomy.
  # Source: Notion "Market data plan" (3912a82d136180d4a99cd1ad45c9122e).
  # All 76 previously ungrouped Market mappings are placed here; nothing is left over.
  @taxonomy_market %{
    category: "Market",
    groups: [
      %{
        name: "Pricing",
        metrics: [
          "daily_avg_price_usd",
          "daily_closing_price_usd",
          "daily_high_price_usd",
          "daily_low_price_usd",
          "daily_opening_price_usd",
          "price_btc",
          "price_btc_change_{{interval}}",
          "price_eth",
          "price_eth_change_{{interval}}",
          "price_histogram",
          "price_usd",
          "price_usd_5m",
          "price_usd_change_1h",
          "price_usd_change_{{interval}}",
          "price_usdt"
        ]
      },
      %{
        name: "Marketcap",
        metrics: [
          "daily_avg_marketcap_usd",
          "daily_closing_marketcap_usd",
          "fully_diluted_valuation_usd",
          "marketcap_usd",
          "marketcap_usd_change_{{interval}}",
          "rank",
          "total_market_2_marketcap_usd",
          "total_market_3_marketcap_usd",
          "total_market_marketcap_usd"
        ]
      },
      %{
        name: "Volume",
        metrics: [
          "daily_trading_volume_usd",
          "volume_dominance",
          "volume_usd",
          "volume_usd_5m",
          "volume_usd_change_{{interval}}"
        ]
      },
      %{
        name: "ETF",
        metrics: [
          "daily_etf_flow",
          "etf_volume_usd_5m",
          "total_etf_flow"
        ]
      },
      %{
        name: "Indicators",
        metrics: [
          "adjusted_price_daa_divergence",
          "btc_s_and_p_price_divergence",
          "money_supply",
          "price_daa_divergence",
          "price_volatility_{{sliding_window}}",
          "rsi_1d",
          "rsi_4h",
          "rsi_7d"
        ]
      },
      %{
        name: "NFT",
        metrics: [
          "nft_collection_avg_price",
          "nft_collection_avg_price_usd",
          "nft_collection_max_price",
          "nft_collection_max_price_usd",
          "nft_collection_min_price",
          "nft_collection_min_price_usd",
          "nft_token_id_price",
          "nft_token_id_price_usd"
        ]
      },
      %{
        name: "Funding Rates",
        metrics: [
          "funding_rate",
          "funding_rates_aggregated_by_exchange",
          "funding_rates_aggregated_by_settlement_currency",
          "total_funding_rates_aggregated_per_asset"
        ]
      },
      %{
        name: "Open Interest",
        metrics: [
          "exchange_open_interest",
          "open_interest_per_settlement_currency",
          "total_open_interest"
        ]
      },
      %{
        name: "Deprecated",
        metrics: [
          "bitfinex_perpetual_funding_rate",
          "bitmex_composite_price_index",
          "bitmex_perpetual_basis",
          "bitmex_perpetual_basis_ratio",
          "bitmex_perpetual_funding_rate",
          "bitmex_perpetual_funding_rate_change_{{interval}}",
          "bitmex_perpetual_open_interest",
          "bitmex_perpetual_open_value",
          "bitmex_perpetual_price",
          "busd_bnb_funding_rates",
          "busd_bnb_open_interest",
          "busd_bnb_open_value",
          "deribit_perpetual_funding_rate",
          "dydx_perpetual_funding_rate",
          "ftx_perpetual_funding_rate",
          "ftx_perpetual_open_interest",
          "huobi_perpetual_funding_rate",
          "usdt_bnb_funding_rates",
          "usdt_bnb_open_interest",
          "usdt_bnb_open_value"
        ]
      }
    ],
    moves: [
      %{metric: "nft_market_volume", to_category: "On-chain Labels", to_group: "NFT"}
    ]
  }

  # Development data package taxonomy.
  # Source: Notion "Development data package" (37d2a82d136180bda65df9debcd27503).
  # All 15 previously ungrouped Development mappings are placed here.
  @taxonomy_development %{
    category: "Development",
    groups: [
      %{
        name: "Development Activity",
        metrics: [
          "30d_moving_avg_dev_activity_change_{{interval}}",
          "dev_activity",
          "dev_activity_1d",
          "dev_activity_change_{{interval}}",
          "ecosystem_dev_activity"
        ]
      },
      %{
        name: "Development Activity Contributors",
        metrics: [
          "dev_activity_contributors_count",
          "dev_activity_contributors_count_7d",
          "ecosystem_dev_activity_contributors_count_7d"
        ]
      },
      %{
        name: "Github Activity",
        metrics: [
          "ecosystem_github_activity",
          "github_activity",
          "github_activity_1d",
          "github_activity_change_{{interval}}"
        ]
      },
      %{
        name: "Github Activity Contributors Count",
        metrics: [
          "ecosystem_github_activity_contributors_count_7d",
          "github_activity_contributors_count",
          "github_activity_contributors_count_7d"
        ]
      }
    ]
  }

  # Social Sentiment package taxonomy.
  # Source: Notion "Social data plan" (37d2a82d136180cf8711e9a0e1f8419c).
  # The four pre-existing groups (Total/Twitter/Telegram/Reddit sentiment) are dissolved
  # into the groups below and then deleted.
  @taxonomy_social %{
    category: "Social",
    groups: [
      %{
        name: "Social Dominance",
        metrics: [
          "social_dominance_4chan",
          "social_dominance_4chan_1h_moving_average",
          "social_dominance_4chan_24h_moving_average",
          "social_dominance_ai_total",
          "social_dominance_ai_total_1h_moving_average",
          "social_dominance_ai_total_24h_moving_average",
          "social_dominance_bitcointalk",
          "social_dominance_bitcointalk_1h_moving_average",
          "social_dominance_bitcointalk_24h_moving_average",
          "social_dominance_discord",
          "social_dominance_professional_traders_chat",
          "social_dominance_reddit",
          "social_dominance_reddit_1h_moving_average",
          "social_dominance_reddit_24h_moving_average",
          "social_dominance_telegram",
          "social_dominance_telegram_1h_moving_average",
          "social_dominance_telegram_24h_moving_average",
          "social_dominance_total",
          "social_dominance_total_1h_moving_average",
          "social_dominance_total_1h_moving_average_change_{{interval}}",
          "social_dominance_total_24h_moving_average",
          "social_dominance_total_24h_moving_average_change_{{interval}}",
          "social_dominance_total_change_{{interval}}",
          "social_dominance_twitter",
          "social_dominance_twitter_1h_moving_average",
          "social_dominance_twitter_24h_moving_average",
          "social_dominance_youtube_videos",
          "social_dominance_youtube_videos_1h_moving_average",
          "social_dominance_youtube_videos_24h_moving_average"
        ]
      },
      %{
        name: "Social Volume",
        metrics: [
          "social_volume_4chan",
          "social_volume_bitcointalk",
          "social_volume_discord",
          "social_volume_professional_traders_chat",
          "social_volume_reddit",
          "social_volume_telegram",
          "social_volume_total",
          "social_volume_total_change_{{interval}}",
          "social_volume_twitter",
          "social_volume_youtube_videos"
        ]
      },
      %{
        name: "Social Volume AI Total",
        metrics: [
          "social_volume_ai_total"
        ]
      },
      %{
        name: "Unique Social Volume",
        metrics: [
          "unique_social_volume_4chan_1d",
          "unique_social_volume_4chan_1h",
          "unique_social_volume_4chan_5m",
          "unique_social_volume_bitcointalk_1d",
          "unique_social_volume_bitcointalk_1h",
          "unique_social_volume_bitcointalk_5m",
          "unique_social_volume_reddit_1d",
          "unique_social_volume_reddit_1h",
          "unique_social_volume_reddit_5m",
          "unique_social_volume_telegram_1d",
          "unique_social_volume_telegram_1h",
          "unique_social_volume_telegram_5m",
          "unique_social_volume_total_1d",
          "unique_social_volume_total_1h",
          "unique_social_volume_total_5m",
          "unique_social_volume_twitter_1d",
          "unique_social_volume_twitter_1h",
          "unique_social_volume_twitter_5m"
        ]
      },
      %{
        name: "Community Social Volume",
        metrics: [
          "community_social_volume_reddit",
          "community_social_volume_telegram"
        ]
      },
      %{
        name: "Categorized Social Volume",
        metrics: [
          "social_volume_twitter_btc_maxi",
          "social_volume_twitter_builder",
          "social_volume_twitter_kol",
          "social_volume_twitter_media",
          "social_volume_twitter_memecoins",
          "social_volume_twitter_trader",
          "social_volume_twitter_trading_firm"
        ]
      },
      %{
        name: "Regular Sentiment",
        rollup: true,
        metrics: []
      },
      %{
        name: "Positive Sentiment",
        also: ["Regular Sentiment"],
        metrics: [
          "sentiment_positive_4chan",
          "sentiment_positive_bitcointalk",
          "sentiment_positive_discord",
          "sentiment_positive_professional_traders_chat",
          "sentiment_positive_reddit",
          "sentiment_positive_telegram",
          "sentiment_positive_total",
          "sentiment_positive_twitter",
          "sentiment_positive_youtube_videos"
        ]
      },
      %{
        name: "Negative Sentiment",
        also: ["Regular Sentiment"],
        metrics: [
          "sentiment_negative_4chan",
          "sentiment_negative_bitcointalk",
          "sentiment_negative_discord",
          "sentiment_negative_professional_traders_chat",
          "sentiment_negative_reddit",
          "sentiment_negative_telegram",
          "sentiment_negative_total",
          "sentiment_negative_twitter",
          "sentiment_negative_youtube_videos"
        ]
      },
      %{
        name: "Sentiment Balance",
        also: ["Regular Sentiment"],
        metrics: [
          "sentiment_balance_4chan",
          "sentiment_balance_bitcointalk",
          "sentiment_balance_discord",
          "sentiment_balance_professional_traders_chat",
          "sentiment_balance_reddit",
          "sentiment_balance_telegram",
          "sentiment_balance_total",
          "sentiment_balance_total_change_{{interval}}",
          "sentiment_balance_twitter",
          "sentiment_balance_youtube_videos"
        ]
      },
      %{
        name: "Weighted Sentiment",
        also: ["Regular Sentiment"],
        metrics: [
          "sentiment_volume_consumed_discord",
          "sentiment_volume_consumed_professional_traders_chat",
          "sentiment_volume_consumed_total_change_{{interval}}",
          "sentiment_weighted_4chan",
          "sentiment_weighted_4chan_1d",
          "sentiment_weighted_4chan_1h",
          "sentiment_weighted_bitcointalk",
          "sentiment_weighted_bitcointalk_1d",
          "sentiment_weighted_bitcointalk_1h",
          "sentiment_weighted_reddit",
          "sentiment_weighted_reddit_1d",
          "sentiment_weighted_reddit_1h",
          "sentiment_weighted_telegram",
          "sentiment_weighted_telegram_1d",
          "sentiment_weighted_telegram_1h",
          "sentiment_weighted_total",
          "sentiment_weighted_total_1d",
          "sentiment_weighted_total_1h",
          "sentiment_weighted_twitter",
          "sentiment_weighted_twitter_1d",
          "sentiment_weighted_twitter_1h",
          "sentiment_weighted_youtube_videos",
          "sentiment_weighted_youtube_videos_1d",
          "sentiment_weighted_youtube_videos_1h"
        ]
      },
      %{
        name: "Bullish/Bearish/Neutral Sentiment",
        rollup: true,
        metrics: []
      },
      %{
        name: "Bullish Sentiment",
        also: ["Bullish/Bearish/Neutral Sentiment"],
        metrics: [
          "sentiment_bullish_4chan",
          "sentiment_bullish_bitcointalk",
          "sentiment_bullish_reddit",
          "sentiment_bullish_telegram",
          "sentiment_bullish_total",
          "sentiment_bullish_twitter",
          "sentiment_bullish_youtube_videos"
        ]
      },
      %{
        name: "Neutral Sentiment",
        also: ["Bullish/Bearish/Neutral Sentiment"],
        metrics: [
          "sentiment_neutral_4chan",
          "sentiment_neutral_bitcointalk",
          "sentiment_neutral_reddit",
          "sentiment_neutral_telegram",
          "sentiment_neutral_total",
          "sentiment_neutral_twitter",
          "sentiment_neutral_youtube_videos"
        ]
      },
      %{
        name: "Bearish Sentiment",
        also: ["Bullish/Bearish/Neutral Sentiment"],
        metrics: [
          "sentiment_bearish_4chan",
          "sentiment_bearish_bitcointalk",
          "sentiment_bearish_reddit",
          "sentiment_bearish_telegram",
          "sentiment_bearish_total",
          "sentiment_bearish_twitter",
          "sentiment_bearish_youtube_videos"
        ]
      },
      %{
        name: "Labeled Social Volume",
        rollup: true,
        metrics: []
      },
      %{
        name: "Positive Docs Count",
        also: ["Labeled Social Volume"],
        metrics: [
          "positive_docs_count_4chan",
          "positive_docs_count_reddit",
          "positive_docs_count_telegram",
          "positive_docs_count_total",
          "positive_docs_count_twitter"
        ]
      },
      %{
        name: "Neutral Docs Count",
        also: ["Labeled Social Volume"],
        metrics: [
          "neutral_docs_count_4chan",
          "neutral_docs_count_reddit",
          "neutral_docs_count_telegram",
          "neutral_docs_count_total",
          "neutral_docs_count_twitter"
        ]
      },
      %{
        name: "Negative Docs Count",
        also: ["Labeled Social Volume"],
        metrics: [
          "negative_docs_count_4chan",
          "negative_docs_count_reddit",
          "negative_docs_count_telegram",
          "negative_docs_count_total",
          "negative_docs_count_twitter"
        ]
      },
      %{
        name: "Sentiment Ratio",
        rollup: true,
        metrics: []
      },
      %{
        name: "Positive Ratio",
        also: ["Sentiment Ratio"],
        metrics: [
          "sentiment_positive_ratio_4chan",
          "sentiment_positive_ratio_4chan_1d",
          "sentiment_positive_ratio_4chan_1h",
          "sentiment_positive_ratio_reddit",
          "sentiment_positive_ratio_reddit_1d",
          "sentiment_positive_ratio_reddit_1h",
          "sentiment_positive_ratio_telegram",
          "sentiment_positive_ratio_telegram_1d",
          "sentiment_positive_ratio_telegram_1h",
          "sentiment_positive_ratio_total",
          "sentiment_positive_ratio_total_1d",
          "sentiment_positive_ratio_total_1h",
          "sentiment_positive_ratio_twitter",
          "sentiment_positive_ratio_twitter_1d",
          "sentiment_positive_ratio_twitter_1h"
        ]
      },
      %{
        name: "Neutral Ratio",
        also: ["Sentiment Ratio"],
        metrics: [
          "sentiment_neutral_ratio_4chan",
          "sentiment_neutral_ratio_4chan_1d",
          "sentiment_neutral_ratio_4chan_1h",
          "sentiment_neutral_ratio_reddit",
          "sentiment_neutral_ratio_reddit_1d",
          "sentiment_neutral_ratio_reddit_1h",
          "sentiment_neutral_ratio_telegram",
          "sentiment_neutral_ratio_telegram_1d",
          "sentiment_neutral_ratio_telegram_1h",
          "sentiment_neutral_ratio_total",
          "sentiment_neutral_ratio_total_1d",
          "sentiment_neutral_ratio_total_1h",
          "sentiment_neutral_ratio_twitter",
          "sentiment_neutral_ratio_twitter_1d",
          "sentiment_neutral_ratio_twitter_1h"
        ]
      },
      %{
        name: "Negative Ratio",
        also: ["Sentiment Ratio"],
        metrics: [
          "sentiment_negative_ratio_4chan",
          "sentiment_negative_ratio_4chan_1d",
          "sentiment_negative_ratio_4chan_1h",
          "sentiment_negative_ratio_reddit",
          "sentiment_negative_ratio_reddit_1d",
          "sentiment_negative_ratio_reddit_1h",
          "sentiment_negative_ratio_telegram",
          "sentiment_negative_ratio_telegram_1d",
          "sentiment_negative_ratio_telegram_1h",
          "sentiment_negative_ratio_total",
          "sentiment_negative_ratio_total_1d",
          "sentiment_negative_ratio_total_1h",
          "sentiment_negative_ratio_twitter",
          "sentiment_negative_ratio_twitter_1d",
          "sentiment_negative_ratio_twitter_1h"
        ]
      },
      %{
        name: "Total Market Sentiment",
        metrics: [
          "sentiment_bb_ratio_selective"
        ]
      },
      %{
        name: "Sentiment Energy",
        metrics: [
          "integral_sentiment_bb",
          "integral_sentiment_bb_1d",
          "integral_sentiment_bb_1h"
        ]
      },
      %{
        name: "Trending Insights",
        metrics: [
          "trending_words_rank"
        ]
      },
      %{
        name: "Community Message Count",
        metrics: [
          "community_messages_count_reddit",
          "community_messages_count_telegram",
          "community_messages_count_total"
        ]
      },
      %{
        name: "Followers",
        metrics: [
          "twitter_followers"
        ]
      },
      %{
        name: "Deprecated",
        metrics: [
          "sentiment_balance_twitter_crypto",
          "sentiment_balance_twitter_news",
          "sentiment_balance_twitter_nft",
          "sentiment_negative_twitter_crypto",
          "sentiment_negative_twitter_news",
          "sentiment_negative_twitter_nft",
          "sentiment_positive_twitter_crypto",
          "sentiment_positive_twitter_news",
          "sentiment_positive_twitter_nft",
          "sentiment_volume_consumed_twitter_crypto",
          "sentiment_volume_consumed_twitter_news",
          "sentiment_volume_consumed_twitter_nft",
          "social_dominance_twitter_crypto",
          "social_dominance_twitter_crypto_1h_moving_average",
          "social_dominance_twitter_crypto_24h_moving_average",
          "social_dominance_twitter_news",
          "social_dominance_twitter_news_1h_moving_average",
          "social_dominance_twitter_news_24h_moving_average",
          "social_dominance_twitter_nft",
          "social_dominance_twitter_nft_1h_moving_average",
          "social_dominance_twitter_nft_24h_moving_average",
          "social_volume_twitter_crypto",
          "social_volume_twitter_news",
          "social_volume_twitter_nft"
        ]
      },
      %{
        name: "Internal Metrics",
        metrics: [
          "mentions_count_4chan",
          "mentions_count_bitcointalk",
          "mentions_count_reddit",
          "mentions_count_telegram",
          "mentions_count_total",
          "mentions_count_twitter",
          "mentions_percentage_1h_total",
          "mentions_percentage_4chan",
          "mentions_percentage_bitcointalk",
          "mentions_percentage_reddit",
          "mentions_percentage_telegram",
          "mentions_percentage_total",
          "mentions_percentage_twitter"
        ]
      }
    ],
    # No renames: "Social Dominance" and "Social Volume" already exist under
    # exactly these names, so their ids and rows are reused.
    # The first four are production's pre-existing groups, "Sentiment" is stage's.
    # A name that does not exist in an environment is a no-op, so the union is
    # listed and the same spec works in both.
    delete_groups: [
      "Total sentiment",
      "Twitter sentiment",
      "Telegram sentiment",
      "Reddit sentiment",
      "Sentiment"
    ]
  }

  # On-chain (Core) package taxonomy.
  # Source: Notion "Onchain core plan" (3842a82d13618064814bf990b6ba1ddb).
  # Network Activity and Network value are roll-ups: their members arrive via `also`
  # from the sub-groups, matching the nesting on the Notion page.
  @taxonomy_onchain %{
    category: "On-chain",
    groups: [
      %{
        name: "Overview",
        metrics: [
          "annual_inflation_rate",
          "gini_index",
          "total_supply"
        ]
      },
      %{
        name: "Fees",
        metrics: [
          "average_fees_usd",
          "average_fees_usd_5m",
          "avg_gas_used",
          "fees",
          "fees_burnt_5m",
          "fees_burnt_usd_5m",
          "fees_intraday",
          "fees_to_network_circulation_usd_1d",
          "fees_usd",
          "fees_usd_intraday",
          "gasUsed",
          "median_fees_usd",
          "median_fees_usd_5m",
          "total_gas_used"
        ]
      },
      %{
        name: "Holders Distribution",
        metrics: [
          "active_holders_distribution_combined_balance_over_{{threshold}}",
          "active_holders_distribution_combined_balance_total",
          "active_holders_distribution_combined_balance_{{low}}_to_{{high}}",
          "active_holders_distribution_over_{{threshold}}",
          "active_holders_distribution_total",
          "active_holders_distribution_{{low}}_to_{{high}}",
          "holders_distribution_combined_balance_over_{{threshold}}",
          "holders_distribution_combined_balance_total",
          "holders_distribution_combined_balance_{{lower}}_to_{{upper}}",
          "holders_distribution_over_{{threshold}}",
          "holders_distribution_total",
          "holders_distribution_{{lower}}_to_{{upper}}",
          "percent_of_active_holders_distribution_combined_balance_{{low}}_to_{{high}}",
          "percent_of_active_holders_distribution_{{low}}_to_{{high}}",
          "percent_of_holders_distribution_combined_balance_{{lower}}_to_{{upper}}",
          "percent_of_holders_distribution_{{lower}}_to_{{upper}}"
        ]
      },
      %{
        name: "Network Activity",
        rollup: true,
        metrics: []
      },
      %{
        name: "Address Activity",
        also: ["Network Activity"],
        metrics: [
          "active_addresses_24h_change_{{interval}}",
          "active_addresses_{{sliding_window}}",
          "daily_active_addresses",
          "daily_network_active_addresses",
          "network_growth",
          "network_growth_change_{{interval}}"
        ]
      },
      %{
        name: "Circulation and Dormancy",
        also: ["Network Activity"],
        metrics: [
          "circulation",
          "circulation_180d_change_{{interval}}",
          "circulation_change_{{interval}}",
          "circulation_usd_180d",
          "circulation_usd_180d_change_{{interval}}",
          "circulation_{{timebound}}",
          "dormant_circulation_365d_change_{{interval}}",
          "dormant_circulation_usd_180d",
          "dormant_circulation_usd_180d_change_{{interval}}",
          "dormant_circulation_{{timebound}}",
          "network_circulation_usd_1d",
          "velocity"
        ]
      },
      %{
        name: "Transaction and Payment",
        also: ["Network Activity"],
        metrics: [
          "average_transfer_5m",
          "median_transfer_5m",
          "payments_count",
          "transaction_volume",
          "transaction_volume_change_{{interval}}",
          "transaction_volume_in_loss",
          "transaction_volume_in_profit",
          "transaction_volume_profit_loss_ratio",
          "transaction_volume_usd",
          "transaction_volume_usd_change_{{interval}}",
          "transactions_count"
        ]
      },
      %{
        name: "Contract-Related",
        also: ["Network Activity"],
        metrics: [
          "contract_interacting_addresses_count",
          "contract_transactions_count",
          "new_deployed_contracts"
        ]
      },
      %{
        name: "Network Value",
        rollup: true,
        metrics: []
      },
      %{
        name: "MVRV and Valuation",
        also: ["Network Value"],
        metrics: [
          "mean_realized_price_usd",
          "mean_realized_price_usd_{{timebound}}",
          "mvrv_long_short_diff_usd",
          "mvrv_usd",
          "mvrv_usd_180d_change_{{interval}}",
          "mvrv_usd_30d_change_{{interval}}",
          "mvrv_usd_365d_change_{{interval}}",
          "mvrv_usd_60d_change_{{interval}}",
          "mvrv_usd_7d_change_{{interval}}",
          "mvrv_usd_90d_change_{{interval}}",
          "mvrv_usd_change_{{interval}}",
          "mvrv_usd_intraday",
          "mvrv_usd_intraday_{{timebound}}",
          "mvrv_usd_z_score",
          "mvrv_usd_{{timebound}}",
          "realized_cap_hodl_waves_{{low}}_to_{{high}}",
          "realized_value_usd",
          "realized_value_usd_{{timebound}}"
        ]
      },
      %{
        name: "Coin Age and Dormant Supply",
        also: ["Network Value"],
        metrics: [
          "age_destroyed",
          "age_destroyed_change_{{interval}}",
          "age_distribution",
          "all_spent_coins_cost",
          "mean_age",
          "mean_age_{{timebound}}",
          "mean_dollar_invested_age",
          "mean_dollar_invested_age_change_{{interval}}",
          "mean_dollar_invested_age_{{timebound}}",
          "percent_of_spent_coins_age_band_{{low}}_to_{{high}}",
          "spent_coins_age_band_{{low}}_to_{{high}}",
          "spent_coins_cost"
        ]
      },
      %{
        name: "Network Profit-Loss and Supply",
        also: ["Network Value"],
        metrics: [
          "network_profit_loss",
          "network_profit_loss_change_{{interval}}",
          "nvt",
          "nvt_5min",
          "nvt_transaction_volume",
          "percent_of_total_supply_in_profit",
          "stock_to_flow",
          "total_supply_in_profit"
        ]
      },
      %{
        name: "Staking",
        metrics: [
          "eth2_roi",
          "eth2_staked_address_count_per_label",
          "eth2_staked_amount_per_label",
          "eth2_stakers_count",
          "eth2_stakers_mvrv_usd_{{timebound}}",
          "eth2_stakers_realized_value_usd_{{timebound}}",
          "eth2_staking_pools",
          "eth2_staking_pools_usd",
          "eth2_staking_pools_validators_count_over_time",
          "eth2_staking_pools_validators_count_over_time_delta",
          "eth2_top_stakers",
          "eth_beacon_deposits",
          "eth_beacon_reward_withdrawals",
          "eth_beacon_validator_withdrawals"
        ]
      },
      %{
        name: "Miners",
        metrics: [
          "avg_difficulty",
          "miners_balance",
          "miners_total_supply"
        ]
      },
      %{
        name: "XRPL Chain",
        metrics: [
          "daily_assets_issued",
          "daily_trustlines_count_change",
          "dex_amm_volume_in_usd_5min",
          "dex_amm_volume_in_xrp_5min",
          "dex_volume_in_usd_5m",
          "dex_volume_in_xrp_5m",
          "liquidity_in_amm_pools_by_asset",
          "liquidity_in_amm_pools_by_pair",
          "total_assets_issued",
          "total_trustlines_count"
        ]
      },
      %{
        name: "NFT",
        metrics: [
          "nft_collection_holders_balance",
          "nft_collection_profit_loss",
          "nft_collection_profit_loss_usd",
          "nft_collection_trades_count",
          "nft_market_count",
          "nft_network_profit_loss",
          "nft_network_profit_loss_usd",
          "nft_trade_volume_usd",
          "nft_trades_count"
        ]
      }
    ],
    # Only two real renames remain. "Holders Distribution" and "Network Value"
    # already match, now that the spec follows the database's Title Case.
    rename_groups: %{"XRP" => "XRPL Chain", "NFT harbor" => "NFT"},
    # The protocol-specific groups are leftovers of the v1 taxonomy - their
    # metrics all live in On-chain Labels now. The union of what production and
    # stage each have is listed; a name absent from an environment is a no-op.
    #
    # "Euler" and "Morpho" hold the nine metrics of `moves` below, which is what
    # lets them be dissolved: a metric that leaves the category counts as placed
    # for the dissolve guard, and the moves run before the deletes.
    delete_groups: [
      "Beacon",
      "ETH 2.0",
      "Defi",
      "Long-term holders",
      "Aave Safety Module",
      "Aave v2",
      "Aave v3",
      "Compound",
      "Compound v3",
      "Makerdao Stats",
      "MakerDAO DSR",
      "Maple",
      "Spark",
      "Fluid",
      "Euler",
      "Morpho",
      "Liquity",
      "Fraxlend",
      "Ethena Staking",
      "Sky Savings",
      "Pendle Markets",
      "crvUSD Savings",
      "GHO Savings",
      "Aggregate Lending and Borrowing Metrics"
    ],
    # Two families leave the category.
    #
    # The first three are the "Move to onchan labels" block at the bottom of the
    # Onchain core plan page. They are listed in the On-chain Labels spec as well;
    # without a move here they would hold a row in both categories, and a metric
    # in two categories is sold by two packages.
    #
    # The rest are the eight `euler_*` and one `morpho_*` metric of Q11 and Q12 -
    # on neither Notion page, in an On-chain protocol group, and answered by
    # product: they go next to the other lending metrics.
    #
    # A move needs its target group to exist, and `onchain_labels` creates those
    # groups earlier in the same `apply!/0`. A first run therefore reports these
    # names as unknown in the labels spec - the row is still in On-chain when
    # that spec is planned - and moves them in when the onchain spec runs.
    moves: [
      %{
        metric: "active_withdrawals",
        to_category: "On-chain Labels",
        to_group: "Centralized Exchanges"
      },
      %{
        metric: "percent_of_total_supply_on_exchanges_change_{{interval}}",
        to_category: "On-chain Labels",
        to_group: "Centralized Exchanges"
      },
      %{
        metric: "holders_labeled_distribution_{{lower}}_to_{{upper}}",
        to_category: "On-chain Labels",
        to_group: "Labeled Supply Distribution"
      },
      %{
        metric: "euler_borrow_apy",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      },
      %{
        metric: "euler_supply_apy",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      },
      %{
        metric: "euler_total_protocol_borrowed_usd",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      },
      %{
        metric: "euler_total_protocol_supplied_usd",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      },
      %{
        metric: "euler_vaults_borrow_apy",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      },
      %{
        metric: "euler_vaults_supply_apy",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      },
      %{
        metric: "euler_vaults_total_borrowed_usd",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      },
      %{
        metric: "euler_vaults_total_supplied_usd",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      },
      %{
        metric: "morpho_supply_apy",
        to_category: "On-chain Labels",
        to_group: "Lending and Borrowing Protocols"
      }
    ]
  }

  # On-chain Labels package taxonomy.
  # Source: Notion "Onchain Labels(final list)" (39c2a82d136180dbb5abd7038901bea4).
  # 104 labeled-entity flow and balance metrics are deliberately NOT placed here -
  # they appear on no group of the page. See docs/metric-taxonomy-open-questions.md.
  @taxonomy_onchain_labels %{
    category: "On-chain Labels",
    groups: [
      %{
        name: "Lending and Borrowing Protocols",
        metrics: [
          "aave_safety_module_amount",
          "aave_safety_module_amount_usd",
          "aave_safety_module_apr",
          "aave_safety_module_emission_usd",
          "aave_safety_module_total_amount_usd",
          "aave_safety_module_total_emission_usd",
          "aave_v2_action_deposits",
          "aave_v2_action_deposits_usd",
          "aave_v2_action_liquidations",
          "aave_v2_action_liquidations_usd",
          "aave_v2_action_new_debt",
          "aave_v2_action_new_debt_usd",
          "aave_v2_action_repayments",
          "aave_v2_action_repayments_usd",
          "aave_v2_active_addresses",
          "aave_v2_protocol_total_borrowed_usd",
          "aave_v2_protocol_total_supplied_usd",
          "aave_v2_revenue",
          "aave_v2_revenue_usd",
          "aave_v2_stable_borrow_apy",
          "aave_v2_supply_apy",
          "aave_v2_total_borrowed",
          "aave_v2_total_borrowed_usd",
          "aave_v2_total_deposits_usd",
          "aave_v2_total_liquidations_usd",
          "aave_v2_total_new_debt_usd",
          "aave_v2_total_protocol_cumulative_revenue_usd",
          "aave_v2_total_protocol_revenue_usd",
          "aave_v2_total_repayments_usd",
          "aave_v2_total_supplied",
          "aave_v2_total_supplied_usd",
          "aave_v2_variable_borrow_apy",
          "aave_v3_action_age_repayments",
          "aave_v3_action_deposits",
          "aave_v3_action_deposits_usd",
          "aave_v3_action_liquidations",
          "aave_v3_action_liquidations_usd",
          "aave_v3_action_new_debt",
          "aave_v3_action_new_debt_usd",
          "aave_v3_action_repayments",
          "aave_v3_action_repayments_usd",
          "aave_v3_active_addresses",
          "aave_v3_flashloan",
          "aave_v3_flashloan_usd",
          "aave_v3_protocol_total_borrowed_usd",
          "aave_v3_protocol_total_supplied_usd",
          "aave_v3_revenue",
          "aave_v3_revenue_usd",
          "aave_v3_supply_apy",
          "aave_v3_total_borrowed",
          "aave_v3_total_borrowed_usd",
          "aave_v3_total_deposits_usd",
          "aave_v3_total_flashloan_usd",
          "aave_v3_total_liquidations_usd",
          "aave_v3_total_new_debt_usd",
          "aave_v3_total_protocol_cumulative_revenue_usd",
          "aave_v3_total_protocol_revenue_usd",
          "aave_v3_total_repayments_usd",
          "aave_v3_total_supplied",
          "aave_v3_total_supplied_usd",
          "aave_v3_variable_borrow_apy",
          "compound_action_deposits",
          "compound_action_deposits_usd",
          "compound_action_liquidations",
          "compound_action_liquidations_usd",
          "compound_action_new_debt",
          "compound_action_new_debt_usd",
          "compound_action_repayments",
          "compound_action_repayments_usd",
          "compound_active_addresses",
          "compound_borrow_apy",
          "compound_protocol_total_borrowed_usd",
          "compound_protocol_total_supplied_usd",
          "compound_revenue",
          "compound_revenue_usd",
          "compound_supply_apy",
          "compound_total_borrowed",
          "compound_total_borrowed_usd",
          "compound_total_deposits_usd",
          "compound_total_liquidations_usd",
          "compound_total_new_debt_usd",
          "compound_total_protocol_cumulative_revenue_usd",
          "compound_total_protocol_revenue_usd",
          "compound_total_repayments_usd",
          "compound_total_supplied",
          "compound_total_supplied_usd",
          "compound_v3_action_deposits",
          "compound_v3_action_deposits_usd",
          "compound_v3_action_liquidations",
          "compound_v3_action_liquidations_usd",
          "compound_v3_action_new_debt",
          "compound_v3_action_new_debt_usd",
          "compound_v3_action_repayments",
          "compound_v3_action_repayments_usd",
          "compound_v3_active_addresses",
          "compound_v3_borrow_apy",
          "compound_v3_collateral_total_supplied",
          "compound_v3_collateral_total_supplied_usd",
          "compound_v3_protocol_total_borrowed_usd",
          "compound_v3_protocol_total_supplied_usd",
          "compound_v3_supply_apy",
          "compound_v3_total_borrowed",
          "compound_v3_total_borrowed_usd",
          "compound_v3_total_deposits_usd",
          "compound_v3_total_liquidations_usd",
          "compound_v3_total_new_debt_usd",
          "compound_v3_total_repayments_usd",
          "compound_v3_total_supplied",
          "compound_v3_total_supplied_usd",
          "dai_created",
          "dai_repaid",
          "euler_action_deposits",
          "euler_action_deposits_usd",
          "euler_action_liquidations",
          "euler_action_liquidations_usd",
          "euler_action_new_debt",
          "euler_action_new_debt_usd",
          "euler_action_repayments",
          "euler_action_repayments_usd",
          "euler_active_addresses",
          "euler_borrow_apy",
          "euler_supply_apy",
          "euler_total_deposits_usd",
          "euler_total_liquidations_usd",
          "euler_total_new_debt_usd",
          "euler_total_protocol_borrowed_usd",
          "euler_total_protocol_supplied_usd",
          "euler_total_repayments_usd",
          "euler_vaults_borrow_apy",
          "euler_vaults_supply_apy",
          "euler_vaults_total_borrowed_usd",
          "euler_vaults_total_supplied_usd",
          "fluid_action_deposits",
          "fluid_action_deposits_usd",
          "fluid_action_liquidations",
          "fluid_action_liquidations_usd",
          "fluid_action_new_debt",
          "fluid_action_new_debt_usd",
          "fluid_action_repayments",
          "fluid_action_repayments_usd",
          "fluid_active_addresses",
          "fluid_protocol_total_supplied_usd",
          "fluid_supply_apy",
          "fluid_total_deposits_usd",
          "fluid_total_liquidations_usd",
          "fluid_total_new_debt_usd",
          "fluid_total_protocol_supplied_usd",
          "fluid_total_repayments_usd",
          "fluid_total_supplied",
          "fluid_total_supplied_usd",
          "fraxlend_action_deposits",
          "fraxlend_action_deposits_usd",
          "fraxlend_action_liquidations",
          "fraxlend_action_liquidations_usd",
          "fraxlend_action_new_debt",
          "fraxlend_action_new_debt_usd",
          "fraxlend_action_repayments",
          "fraxlend_action_repayments_usd",
          "fraxlend_active_addresses",
          "fraxlend_borrow_apy",
          "fraxlend_protocol_total_borrowed_usd",
          "fraxlend_protocol_total_supplied_usd",
          "fraxlend_total_borrowed_against_collateral",
          "fraxlend_total_deposits_usd",
          "fraxlend_total_liquidations_usd",
          "fraxlend_total_new_debt_usd",
          "fraxlend_total_repayments_usd",
          "fraxlend_total_supplied",
          "fraxlend_total_supplied_usd",
          "liquity_action_deposits",
          "liquity_action_deposits_usd",
          "liquity_action_liquidations",
          "liquity_action_liquidations_usd",
          "liquity_action_new_debt",
          "liquity_action_new_debt_usd",
          "liquity_action_repayments",
          "liquity_action_repayments_usd",
          "liquity_active_addresses",
          "liquity_borrow_fee",
          "liquity_total_borrowed",
          "liquity_total_borrowed_usd",
          "liquity_total_supplied",
          "liquity_total_supplied_usd",
          "makerdao_action_deposits",
          "makerdao_action_deposits_usd",
          "makerdao_action_liquidations",
          "makerdao_action_liquidations_usd",
          "makerdao_action_new_debt",
          "makerdao_action_new_debt_usd",
          "makerdao_action_repayments",
          "makerdao_action_repayments_filtered",
          "makerdao_action_repayments_usd",
          "makerdao_active_addresses",
          "makerdao_bite_keeper_balance",
          "makerdao_cdp_owner_balance",
          "makerdao_dsr_deposits",
          "makerdao_dsr_total_supplied",
          "makerdao_dsr_withdrawals",
          "makerdao_protocol_total_borrowed_usd",
          "makerdao_protocol_total_supplied_usd",
          "makerdao_total_borrowed",
          "makerdao_total_borrowed_usd",
          "makerdao_total_deposits_usd",
          "makerdao_total_liquidations_usd",
          "makerdao_total_new_debt_usd",
          "makerdao_total_repayments_usd",
          "makerdao_total_supplied",
          "makerdao_total_supplied_usd",
          "maple_action_deposits",
          "maple_action_deposits_usd",
          "maple_action_new_debt",
          "maple_action_new_debt_usd",
          "maple_action_repayments",
          "maple_action_repayments_usd",
          "maple_active_addresses",
          "maple_protocol_total_borrowed_usd",
          "maple_protocol_total_supplied_usd",
          "maple_total_borrowed",
          "maple_total_borrowed_usd",
          "maple_total_deposits_usd",
          "maple_total_new_debt_usd",
          "maple_total_repayments_usd",
          "maple_total_supplied",
          "maple_total_supplied_usd",
          "mcd_collat_ratio",
          "mcd_dsr",
          "mcd_stability_fee",
          "morpho_action_age_repayments",
          "morpho_action_deposits",
          "morpho_action_deposits_usd",
          "morpho_action_liquidations",
          "morpho_action_liquidations_usd",
          "morpho_action_new_debt",
          "morpho_action_new_debt_usd",
          "morpho_action_repayments",
          "morpho_action_repayments_usd",
          "morpho_active_addresses",
          "morpho_flashloan",
          "morpho_flashloan_usd",
          "morpho_protocol_total_borrowed_usd",
          "morpho_protocol_total_supplied_usd",
          "morpho_supply_apy",
          "morpho_total_deposits_usd",
          "morpho_total_flashloan_usd",
          "morpho_total_liquidations_usd",
          "morpho_total_new_debt_usd",
          "morpho_total_repayments_usd",
          "morpho_vaults_apy",
          "morpho_vaults_total_supplied_usd",
          "spark_action_age_repayments",
          "spark_action_deposits",
          "spark_action_deposits_usd",
          "spark_action_liquidations",
          "spark_action_liquidations_usd",
          "spark_action_new_debt",
          "spark_action_new_debt_usd",
          "spark_action_repayments",
          "spark_action_repayments_usd",
          "spark_active_addresses",
          "spark_borrow_apy",
          "spark_flashloan",
          "spark_flashloan_usd",
          "spark_protocol_total_borrowed_usd",
          "spark_protocol_total_supplied_usd",
          "spark_supply_apy",
          "spark_total_borrowed",
          "spark_total_borrowed_usd",
          "spark_total_deposits_usd",
          "spark_total_flashloan_usd",
          "spark_total_liquidations_usd",
          "spark_total_new_debt_usd",
          "spark_total_repayments_usd",
          "spark_total_supplied",
          "spark_total_supplied_usd",
          "total_dai_created"
        ]
      },
      %{
        name: "Aggregated Lending and Borrowing Metrics",
        metrics: [
          "total_lending_liquidations_non_stablecoins_usd",
          "total_lending_liquidations_stablecoins_usd",
          "total_lending_new_debt_non_stablecoins_usd",
          "total_lending_new_debt_stablecoins_usd",
          "total_lending_repayments_non_stablecoins_usd",
          "total_lending_repayments_stablecoins_usd"
        ]
      },
      %{
        name: "Yield, Savings & Staking",
        metrics: [
          "crvusd_savings_apy",
          "crvusd_savings_distributions",
          "crvusd_savings_total_supplied",
          "ethena_staking_apy",
          "ethena_staking_deposits",
          "ethena_staking_withdrawals",
          "gho_savings_deposits",
          "gho_savings_total_supplied",
          "gho_savings_withdrawals",
          "pendle_implied_apy",
          "pendle_total_markets_tvl",
          "pendle_underlying_apy",
          "pendle_yield_spread",
          "sky_savings_apy",
          "sky_savings_deposits",
          "sky_savings_total_supplied",
          "sky_savings_withdrawals"
        ]
      },
      %{
        name: "DEXes",
        metrics: [
          "eth_based_trade_amount_by_dex",
          "eth_based_trade_volume_by_dex",
          "eth_trade_volume_by_token",
          "other_trade_amount_by_dex",
          "other_trade_volume_by_dex",
          "stablecoin_trade_amount_by_dex",
          "stablecoin_trade_volume_by_dex",
          "stablecoin_trade_volume_by_token",
          "token_eth_price_by_dex_5m",
          "total_trade_amount_by_dex",
          "total_trade_volume_by_dex"
        ]
      },
      %{
        name: "NFT",
        # `nft_market_volume` arrives here from Market via that spec's `moves`.
        # It has to be listed at the destination as well, or the row the move
        # creates belongs to no group the spec claims: it gets no display_order
        # and is reported as unrequested forever.
        #
        # On a database where the move has not run yet this name has no mapping
        # row in On-chain Labels, so the first `apply!/0` reports it under
        # `unknown` for this spec and the move lands afterwards in the same run.
        # A second `apply!/0` then gives it its display_order. Everything else is
        # complete after one pass.
        metrics: [
          "nft_market_volume",
          "nft_retail_trade_volume_usd",
          "nft_retail_trades_count",
          "nft_whale_trade_volume_usd",
          "nft_whale_trades_count"
        ]
      },
      %{
        name: "Centralized Exchanges",
        metrics: [
          "active_deposits",
          "active_deposits_5m",
          "active_deposits_per_exchange",
          "active_withdrawals",
          "active_withdrawals_5m",
          "active_withdrawals_per_exchange",
          "deposit_transactions",
          "deposit_transactions_5m",
          "deposit_transactions_per_exchange",
          "exchange_balance",
          "exchange_balance_change_{{interval}}",
          "exchange_inflow",
          "exchange_inflow_change_{{interval}}",
          "exchange_inflow_per_exchange",
          "exchange_inflow_usd",
          "exchange_inflow_usd_change_{{interval}}",
          "exchange_outflow",
          "exchange_outflow_change_{{interval}}",
          "exchange_outflow_per_exchange",
          "exchange_outflow_usd",
          "exchange_outflow_usd_change_{{interval}}",
          "percent_of_total_supply_on_exchanges",
          "percent_of_total_supply_on_exchanges_change_{{interval}}",
          "supply_on_exchanges",
          "supply_outside_exchanges",
          "withdrawal_transactions",
          "withdrawal_transactions_5m",
          "withdrawal_transactions_per_exchange"
        ]
      },
      %{
        name: "Whales",
        metrics: [
          "whale_transaction_count_100k_usd_to_inf",
          "whale_transaction_count_100k_usd_to_inf_change_{{interval}}",
          "whale_transaction_count_1m_usd_to_inf",
          "whale_transaction_count_1m_usd_to_inf_change_{{interval}}",
          "whale_transaction_volume_100k_usd_to_inf",
          "whale_transaction_volume_1m_usd_to_inf"
        ]
      },
      %{
        name: "Labeled Supply Distribution",
        metrics: [
          "holders_labeled_distribution_combined_balance_total",
          "holders_labeled_distribution_combined_balance_{{lower}}_to_{{upper}}",
          "holders_labeled_distribution_total",
          "holders_labeled_distribution_{{lower}}_to_{{upper}}",
          "holders_labeled_negative_distribution_combined_balance_total",
          "holders_labeled_negative_distribution_combined_balance_{{lower}}_to_{{upper}}",
          "holders_labeled_negative_distribution_total",
          "holders_labeled_negative_distribution_{{lower}}_to_{{upper}}"
        ]
      },
      %{
        name: "Top Holders",
        metrics: [
          "amount_in_exchange_top_holders",
          "amount_in_non_exchange_top_holders",
          "amount_in_top_holders"
        ]
      },
      %{
        name: "Labeled Balances",
        metrics: [
          "balance_per_label_and_owner_delta",
          "balance_per_owner"
        ]
      },
      %{
        name: "Deprecated",
        metrics: [
          "cex_balance",
          "combined_historical_balance_centralized_exchanges",
          "combined_historical_balance_decentralized_exchanges",
          "combined_historical_balance_funds",
          "defi_exchange_balance",
          "defi_to_exchanges_flow",
          "defi_total_value_locked_eth",
          "defi_total_value_locked_usd",
          "deposit_balance",
          "dex_balance",
          "dex_trader_balance",
          "dex_traders_exchange_balance",
          "dex_traders_to_exchanges_flow",
          "exchanges_to_defi_flow",
          "exchanges_to_dex_traders_flow",
          "exchanges_to_genesis_flow",
          "exchanges_to_miners_flow",
          "exchanges_to_other_flow",
          "exchanges_to_traders_flow",
          "exchanges_to_whales_flow",
          "genesis_exchange_balance",
          "genesis_to_exchanges_flow",
          "historical_balance_centralized_exchanges",
          "historical_balance_decentralized_exchanges",
          "historical_balance_whales_usd",
          "labelled_exchange_balance_sum",
          "labelled_historical_balance",
          "labelled_historical_balance_changes",
          "mcd_collat_ratio_sai",
          "mcd_collat_ratio_weth",
          "mcd_liquidation",
          "mcd_locked_token",
          "miners_exchange_balance",
          "miners_to_exchanges_flow",
          "other_exchange_balance",
          "other_to_exchanges_flow",
          "percent_of_whale_stablecoin_total_supply",
          "scd_collat_ratio",
          "scd_locked_token",
          "traders_exchange_balance",
          "traders_to_exchanges_flow",
          "uniswap_claims_amount",
          "uniswap_claims_count",
          "uniswap_lp_claims_amount",
          "uniswap_lp_claims_count",
          "uniswap_top_claimers",
          "uniswap_total_claims_amount",
          "uniswap_total_claims_count",
          "uniswap_total_claims_percent",
          "uniswap_total_lp_claims_amount",
          "uniswap_total_lp_claims_count",
          "uniswap_total_user_claims_amount",
          "uniswap_total_user_claims_count",
          "uniswap_user_claims_amount",
          "uniswap_user_claims_count",
          "whale_balance",
          "whales_exchange_balance",
          "whales_to_exchanges_flow",
          "withdrawal_balance"
        ]
      }
    ],
    # "Top Holders" is deliberately absent: it already exists under exactly this
    # name, so it is reused, keeping its id and its three `amount_in_*` rows.
    # `topHoldersPercentOfTotalSupply` therefore stays put instead of blocking a
    # dissolve, which is what it did while the spec called the group
    # "Top holders" (Q6 becomes a cleanup, not a blocker).
    delete_groups: [
      "Exchanges",
      "Exchange Users",
      "Exchanges 2.0",
      "Funds",
      "Miners",
      "DeFi"
    ],
    # Reusing "Top Holders" leaves its current rows alone, and three of them
    # belong elsewhere by this spec. Without these removals each would sit in two
    # groups at once.
    remove_from_groups: %{
      "Top Holders" => [
        "percent_of_whale_stablecoin_total_supply",
        "whale_transaction_count_100k_usd_to_inf",
        "whale_transaction_count_1m_usd_to_inf"
      ]
    }
  }

  # Apply order. `market` moves nft_market_volume into On-chain Labels / NFT, so
  # onchain_labels has to exist first or that one move is refused and reported.
  @specs [
    {"onchain_labels", @taxonomy_onchain_labels},
    {"market", @taxonomy_market},
    {"development", @taxonomy_development},
    {"onchain", @taxonomy_onchain},
    {"social", @taxonomy_social}
  ]

  # Reading order of the packages on the Notion index, which is the order
  # /available_metrics lists them in. Categories are shared by all five specs, so
  # this is applied once per run rather than per spec. A name that does not exist
  # in an environment is skipped.
  @category_display_order [
    "Market",
    "Development",
    "Social",
    "On-chain",
    "On-chain Labels"
  ]

  @doc ~s"""
  The names of the available specs, in apply order.
  """
  @spec specs() :: [String.t()]
  def specs, do: Enum.map(@specs, &elem(&1, 0))

  @doc ~s"""
  Compute what would change and print a report. Writes nothing.

  Pass a list of spec names to narrow it, e.g. `plan(["market", "development"])`.
  Returns the plans, so they can be inspected further if the report is not enough.
  """
  @spec plan([String.t()]) :: [map()]
  def plan(names \\ []) do
    plans = names |> selected_specs() |> Enum.map(fn {name, spec} -> build_plan(name, spec) end)

    Enum.each(plans, &print_plan/1)
    print_category_order(category_order_plan())
    print_summary(plans, false)

    plans
  end

  @doc ~s"""
  Apply the taxonomy. Each spec runs in its own transaction.

  Reports each spec and then writes it, one spec per transaction, in `@specs`
  order. Returns which specs were applied and which were refused.

  `@specs` puts `onchain_labels` first because `market` moves
  `nft_market_volume` into On-chain Labels / NFT, and a move needs its target
  group to already exist. Because each spec is planned right before it runs, a
  single `apply!/0` is enough - the group exists by the time `market` is planned.

  `plan/0` cannot see that: it plans all five against the database as it is now,
  so it reports the move as refused until `onchain_labels` has actually been
  applied. That refusal in a dry run is expected, not a problem. Applying only
  `market` on a database where the group does not exist yet *is* refused, and
  reported rather than half-done.
  """
  @spec apply!([String.t()]) :: %{applied: [String.t()], refused: [String.t()]}
  def apply!(names \\ []) do
    # Each spec is planned immediately before it is executed, not all up front.
    # A `moves` entry needs the target category's group to exist, and that group
    # is created by an earlier spec in the same run - planning everything first
    # would compute the move against a database state that no longer holds by the
    # time it runs, and refuse a move that is in fact fine.
    plans =
      names
      |> selected_specs()
      |> Enum.map(fn {name, spec} ->
        plan = build_plan(name, spec)
        print_plan(plan)

        unless Map.has_key?(plan, :error), do: execute(plan)

        plan
      end)

    apply_category_order!()
    print_summary(plans, true)
    log("done")

    {refused, applied} = Enum.split_with(plans, &Map.has_key?(&1, :error))

    %{applied: Enum.map(applied, & &1.name), refused: Enum.map(refused, & &1.name)}
  end

  @doc ~s"""
  Renumber `metric_categories.display_order` to `@category_display_order`.

  Called by `apply!/1` - the categories are shared by every spec, so the order is
  a property of the taxonomy as a whole rather than of one package. Idempotent,
  and exposed on its own so the order can be fixed without touching mappings.
  """
  @spec apply_category_order!() :: :ok
  def apply_category_order! do
    changes = category_order_plan()

    print_category_order(changes)

    Enum.each(changes, fn %{category: category, to: display_order} ->
      {:ok, _} = MetricCategory.update(category, %{display_order: display_order})
    end)
  end

  @doc ~s"""
  Plan a spec map that is not one of the checked-in files. Returns the plan and
  prints nothing.

  Exists so the behaviour can be tested against a small fixture instead of the
  1000-metric production taxonomy.
  """
  @spec plan_spec(String.t(), map()) :: map()
  def plan_spec(name, spec) when is_binary(name) and is_map(spec), do: build_plan(name, spec)

  @doc ~s"""
  Apply a spec map that is not one of the checked-in files. See `plan_spec/2`.
  """
  @spec apply_spec!(String.t(), map()) :: :ok | {:refused, String.t()}
  def apply_spec!(name, spec) when is_binary(name) and is_map(spec) do
    case build_plan(name, spec) do
      %{error: error} -> {:refused, error}
      plan -> execute(plan)
    end
  end

  defp selected_specs([]), do: @specs

  defp selected_specs(names) when is_list(names) do
    unknown = names -- specs()

    if unknown != [] do
      raise ArgumentError,
            "Unknown spec(s): #{Enum.join(unknown, ", ")}. Known: #{Enum.join(specs(), ", ")}."
    end

    Enum.filter(@specs, fn {name, _spec} -> name in names end)
  end

  # ---------------------------------------------------------------- planning

  # A plan is computed against the current database contents and then executed
  # in one transaction. Planning and executing are separate so that the report a
  # dry run prints is exactly what an apply would do.
  defp build_plan(name, spec) do
    case Repo.get_by(MetricCategory, name: spec.category) do
      nil ->
        %{name: name, spec: spec, error: "category #{inspect(spec.category)} does not exist"}

      category ->
        renames = plan_renames(spec, category)
        existing_groups = groups_after_renames(category, renames)
        group_plan = plan_groups(spec, category, existing_groups)
        mappings = load_mappings(category.id)

        desired = desired_memberships(spec)
        identities = identities(mappings)

        {known, unknown} = Map.split(desired, Map.keys(identities))

        %{
          name: name,
          spec: spec,
          category: category,
          renames: renames,
          groups: group_plan,
          identities: identities,
          desired: known,
          unknown: unknown |> Map.keys() |> Enum.sort(),
          inserts: plan_inserts(known, mappings, group_plan, identities, existing_groups),
          ungrouped_deletions: plan_ungrouped_deletions(known, mappings),
          unplaced: plan_unplaced(spec, known, mappings),
          extra: plan_extra(known, mappings, existing_groups, spec),
          group_deletions: plan_group_deletions(spec, existing_groups, known, mappings),
          row_removals: plan_row_removals(spec, existing_groups, known, mappings),
          moves: plan_moves(spec, mappings)
        }
    end
  end

  defp plan_renames(spec, category) do
    for {from, to} <- Map.get(spec, :rename_groups, %{}),
        group = MetricGroup.get_by_name_and_category(from, category.id),
        not is_nil(group),
        renameable?(to, category, group) do
      {group, to}
    end
  end

  # Renaming into a name that is already taken by a *different* group would hit
  # the unique index on (name, category_id). Report it instead of crashing.
  defp renameable?(to, category, group) do
    case MetricGroup.get_by_name_and_category(to, category.id) do
      nil -> true
      %MetricGroup{id: id} -> id == group.id
    end
  end

  defp groups_after_renames(category, renames) do
    renamed = Map.new(renames, fn {group, to} -> {group.id, to} end)

    category.id
    |> MetricGroup.list_by_category()
    |> Enum.map(fn group ->
      case Map.fetch(renamed, group.id) do
        {:ok, new_name} -> %{group | name: new_name}
        :error -> group
      end
    end)
  end

  # The spec's group order is the display order. Existing groups keep their id.
  defp plan_groups(spec, _category, existing_groups) do
    by_name = Map.new(existing_groups, &{&1.name, &1})

    spec.groups
    |> Enum.with_index(1)
    |> Enum.map(fn {group_spec, display_order} ->
      %{
        name: group_spec.name,
        display_order: display_order,
        existing: Map.get(by_name, group_spec.name)
      }
    end)
  end

  defp load_mappings(category_id) do
    from(m in MetricCategoryMapping,
      where: m.category_id == ^category_id,
      preload: [:metric_registry]
    )
    |> Repo.all()
  end

  # The name a mapping row stands for. Registry templates keep their braces -
  # that is how they are stored and how the Notion tables write them.
  defp mapping_name(%{metric_registry: %{metric: metric}}) when is_binary(metric), do: metric
  defp mapping_name(%{metric_registry_id: nil, metric: metric}) when is_binary(metric), do: metric
  defp mapping_name(_), do: nil

  # How to write a new row for a metric: either its registry id, or its
  # module/metric pair. Taken from a row that already exists rather than resolved
  # from scratch, which is what stops the importer inventing a metric.
  defp identities(mappings) do
    Enum.reduce(mappings, %{}, fn mapping, acc ->
      case mapping_name(mapping) do
        nil ->
          acc

        name ->
          identity =
            if mapping.metric_registry_id do
              %{metric_registry_id: mapping.metric_registry_id}
            else
              %{module: mapping.module, metric: mapping.metric}
            end

          Map.put_new(acc, name, identity)
      end
    end)
  end

  # metric name => MapSet of the group names it should belong to
  defp desired_memberships(spec) do
    Enum.reduce(spec.groups, %{}, fn group_spec, acc ->
      groups = [group_spec.name | Map.get(group_spec, :also, [])]

      Enum.reduce(group_spec.metrics, acc, fn metric, inner ->
        Map.update(inner, metric, MapSet.new(groups), &MapSet.union(&1, MapSet.new(groups)))
      end)
    end)
  end

  defp plan_inserts(desired, mappings, group_plan, identities, existing_groups) do
    group_names = Map.new(existing_groups, &{&1.id, &1.name})
    order = Map.new(group_plan, &{&1.name, &1.display_order})

    for {metric, wanted} <- desired,
        missing = MapSet.difference(wanted, current_groups(mappings, metric, group_names)),
        group_name <- MapSet.to_list(missing) do
      %{
        metric: metric,
        group: group_name,
        identity: Map.fetch!(identities, metric),
        group_order: Map.get(order, group_name, 999)
      }
    end
  end

  defp current_groups(mappings, metric_name, group_names) do
    for mapping <- mappings,
        mapping_name(mapping) == metric_name,
        not is_nil(mapping.group_id),
        name = group_names[mapping.group_id],
        not is_nil(name),
        into: MapSet.new(),
        do: name
  end

  defp plan_ungrouped_deletions(desired, mappings) do
    Enum.filter(mappings, fn mapping ->
      is_nil(mapping.group_id) and Map.has_key?(desired, mapping_name(mapping))
    end)
  end

  # Ungrouped rows for metrics the spec never names. `unknown` is the mirror of
  # this - a spec name with no row - and `extra` covers *grouped* rows the spec
  # did not ask for. Without this third list a metric that is in the category and
  # in neither the spec nor a group is invisible in the report and stays
  # ungrouped forever.
  #
  # A metric in `moves` is not in `desired` - it is leaving the category, not
  # joining a group here - so it has to be excluded explicitly or it reads as
  # forgotten when it is the opposite.
  defp plan_unplaced(spec, desired, mappings) do
    moved = MapSet.new(Map.get(spec, :moves, []), & &1.metric)

    for mapping <- mappings,
        is_nil(mapping.group_id),
        name = mapping_name(mapping),
        not is_nil(name),
        not Map.has_key?(desired, name),
        not MapSet.member?(moved, name),
        uniq: true,
        do: name
  end

  # Grouped rows the spec does not ask for. Reported, never deleted - an admin
  # may have added one deliberately, and guessing wrong revokes paid access.
  defp plan_extra(desired, mappings, existing_groups, spec) do
    group_names = Map.new(existing_groups, &{&1.id, &1.name})
    doomed = MapSet.new(Map.get(spec, :delete_groups, []))

    removals =
      for {group, metrics} <- Map.get(spec, :remove_from_groups, %{}),
          metric <- metrics,
          into: MapSet.new(),
          do: {group, metric}

    Enum.filter(mappings, fn mapping ->
      name = mapping_name(mapping)
      group = group_names[mapping.group_id]

      not is_nil(group) and not is_nil(name) and
        not MapSet.member?(doomed, group) and
        not MapSet.member?(removals, {group, name}) and
        not MapSet.member?(Map.get(desired, name, MapSet.new()), group)
    end)
  end

  # A group can only be dissolved when every metric in it is placed elsewhere by
  # this spec. Otherwise the delete drops the metric out of the taxonomy, and
  # nothing downstream would notice.
  #
  # A metric in `moves` is placed too - in another category. Its row leaves the
  # group before the dissolve rather than being deleted with it, so it is neither
  # an orphan nor one of the rows to delete. `execute/1` relies on that: it runs
  # the moves first, and would otherwise delete the row it had just moved.
  defp plan_group_deletions(spec, existing_groups, desired, mappings) do
    moved = MapSet.new(Map.get(spec, :moves, []), & &1.metric)

    for name <- Map.get(spec, :delete_groups, []),
        group = Enum.find(existing_groups, &(&1.name == name)),
        not is_nil(group) do
      {moving, rows} =
        mappings
        |> Enum.filter(&(&1.group_id == group.id))
        |> Enum.split_with(&MapSet.member?(moved, mapping_name(&1)))

      orphans =
        rows
        |> Enum.map(&mapping_name/1)
        |> Enum.reject(&(is_nil(&1) or Map.has_key?(desired, &1)))
        |> Enum.uniq()
        |> Enum.sort()

      %{group: group, rows: rows, moving: moving, orphans: orphans}
    end
  end

  # `remove_from_groups` is the per-row counterpart of `delete_groups`: the group
  # is being kept, but one metric in it belongs somewhere else. Needed when an
  # existing group is reused rather than dissolved - reuse leaves its current
  # rows alone, so a metric the spec puts elsewhere would end up in two groups.
  #
  # Same guard as a dissolve: the row is only removed when the spec places the
  # metric somewhere, so this can never be the last row a metric has.
  defp plan_row_removals(spec, existing_groups, desired, mappings) do
    for {group_name, metrics} <- Map.get(spec, :remove_from_groups, %{}),
        group = Enum.find(existing_groups, &(&1.name == group_name)),
        not is_nil(group),
        metric <- metrics,
        row = Enum.find(mappings, &(&1.group_id == group.id and mapping_name(&1) == metric)),
        not is_nil(row) do
      %{group: group, metric: metric, row: row, placed?: Map.has_key?(desired, metric)}
    end
  end

  defp plan_moves(spec, mappings) do
    for move <- Map.get(spec, :moves, []) do
      target = Repo.get_by(MetricCategory, name: move.to_category)
      target_group = target && MetricGroup.get_by_name_and_category(move.to_group, target.id)

      %{
        move: move,
        rows: Enum.filter(mappings, &(mapping_name(&1) == move.metric)),
        target: target,
        target_group: target_group
      }
    end
  end

  # ---------------------------------------------------------------- reporting

  defp print_plan(%{error: error, name: name}), do: log("#{name}: REFUSED - #{error}")

  defp print_plan(plan) do
    new_groups = Enum.count(plan.groups, &is_nil(&1.existing))

    log("""
    #{plan.name} (category #{inspect(plan.spec.category)}, id #{plan.category.id})
      groups:              #{length(plan.groups)} in spec, #{new_groups} to create, #{length(plan.renames)} to rename
      mapping rows:        #{length(plan.inserts)} to insert
      ungrouped rows:      #{length(plan.ungrouped_deletions)} to delete (metric is now grouped)
      groups to dissolve:  #{length(plan.group_deletions)}
      rows to remove:      #{length(plan.row_removals)} (kept group, wrong metric)
      moves out:           #{length(plan.moves)}
      unknown metrics:     #{length(plan.unknown)}
      unplaced metrics:    #{length(plan.unplaced)} (in the category, in no group, not in the spec)
      unrequested rows:    #{length(plan.extra)} (left alone)\
    """)

    Enum.each(plan.renames, fn {group, to} ->
      log("  rename group #{inspect(group.name)} -> #{inspect(to)} (id #{group.id})")
    end)

    if plan.unknown != [] do
      log(
        "  unknown (no mapping row in this category, skipped): #{Enum.join(plan.unknown, ", ")}"
      )
    end

    if plan.unplaced != [] do
      log(
        "  unplaced (ungrouped, and the spec does not name them): " <>
          Enum.join(Enum.sort(plan.unplaced), ", ")
      )
    end

    Enum.each(plan.group_deletions, fn
      %{group: group, orphans: [], rows: rows} ->
        log("  dissolve group #{inspect(group.name)} (#{length(rows)} rows)")

      %{group: group, orphans: orphans} ->
        log(
          "  REFUSE to dissolve #{inspect(group.name)} - not placed by the spec: " <>
            Enum.join(orphans, ", ")
        )
    end)

    Enum.each(plan.row_removals, fn
      %{placed?: true, metric: metric, group: group} ->
        log("  remove #{metric} from group #{inspect(group.name)} (placed elsewhere)")

      %{metric: metric, group: group} ->
        log(
          "  REFUSE to remove #{metric} from #{inspect(group.name)} - " <>
            "the spec does not place it anywhere else"
        )
    end)

    Enum.each(plan.moves, &print_move/1)

    if plan.extra != [] do
      names = plan.extra |> Enum.map(&mapping_name/1) |> Enum.uniq() |> Enum.sort()
      log("  unrequested grouped rows (kept): #{Enum.join(names, ", ")}")
    end
  end

  defp print_move(%{move: move, target: nil}),
    do: log("  REFUSE move #{move.metric} - category #{inspect(move.to_category)} does not exist")

  defp print_move(%{move: move, target_group: nil}),
    do:
      log(
        "  REFUSE move #{move.metric} - group #{inspect(move.to_group)} missing in " <>
          "#{inspect(move.to_category)}; apply that category's spec first"
      )

  defp print_move(%{move: move, rows: rows}),
    do:
      log(
        "  move #{move.metric} -> #{move.to_category} / #{move.to_group} (#{length(rows)} rows)"
      )

  # Only the categories whose order is wrong, in target order. A category named in
  # the list but missing from this environment is skipped, same as a group name.
  defp category_order_plan do
    existing = Map.new(MetricCategory.list_ordered(), &{&1.name, &1})

    @category_display_order
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {name, display_order} ->
      case Map.get(existing, name) do
        nil -> []
        %{display_order: ^display_order} -> []
        category -> [%{category: category, from: category.display_order, to: display_order}]
      end
    end)
  end

  defp print_category_order([]), do: log("category order: already correct")

  defp print_category_order(changes) do
    log("category order: #{length(changes)} to renumber")

    Enum.each(changes, fn %{category: category, from: from, to: to} ->
      log("  #{category.name}: #{inspect(from)} -> #{to}")
    end)
  end

  defp print_summary(plans, apply?) do
    runnable = Enum.reject(plans, &Map.has_key?(&1, :error))
    sum = fn key -> runnable |> Enum.map(&length(Map.fetch!(&1, key))) |> Enum.sum() end

    log("""
    ---
    #{length(plans)} spec(s), #{length(plans) - length(runnable)} refused
    #{sum.(:inserts)} mapping rows to insert, #{sum.(:ungrouped_deletions)} ungrouped rows to delete
    #{sum.(:unknown)} unknown metric name(s), #{sum.(:unplaced)} unplaced, #{sum.(:extra)} unrequested row(s) left alone
    mode: #{if apply?, do: "APPLY", else: "dry run - nothing written"}\
    """)
  end

  # --------------------------------------------------------------- executing

  defp execute(plan) do
    Repo.transaction(
      fn ->
        Enum.each(plan.renames, fn {group, to} ->
          {:ok, _} = MetricGroup.update(group, %{name: to})
        end)

        group_ids = upsert_groups(plan)

        Enum.each(plan.inserts, fn insert ->
          attrs =
            insert.identity
            |> Map.put(:category_id, plan.category.id)
            |> Map.put(:group_id, Map.fetch!(group_ids, insert.group))

          {:ok, _} = MetricCategoryMapping.create_if_not_exists(attrs)
        end)

        Enum.each(plan.ungrouped_deletions, &Repo.delete!/1)

        Enum.each(plan.row_removals, fn
          %{placed?: true, row: row} -> Repo.delete!(row)
          _refused -> :ok
        end)

        # Before the dissolves: a moved row keeps its id and would be deleted
        # along with the group it is leaving.
        Enum.each(plan.moves, fn
          %{target: nil} -> :ok
          %{target_group: nil} -> :ok
          %{rows: rows, target: target, target_group: group} -> move_rows(rows, target, group)
        end)

        Enum.each(plan.group_deletions, fn
          %{orphans: [], rows: rows, group: group} ->
            Enum.each(rows, &Repo.delete!/1)
            Repo.delete!(group)

          _refused ->
            :ok
        end)

        renumber_mappings(plan, group_ids)
      end,
      timeout: :infinity
    )
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> raise "taxonomy spec #{plan.name} failed: #{inspect(reason)}"
    end
  end

  # The row keeps the display_order it had in the group it is leaving, which
  # collides with whatever already holds that number in the target group. Park it
  # after the last row there instead; the next apply of the target's own spec
  # renumbers the group into spec order.
  defp move_rows(rows, target, group) do
    rows
    |> Enum.with_index(last_display_order(group.id) + 1)
    |> Enum.each(fn {row, display_order} ->
      {:ok, _} =
        MetricCategoryMapping.update(row, %{
          category_id: target.id,
          group_id: group.id,
          display_order: display_order
        })
    end)
  end

  defp last_display_order(group_id) do
    from(m in MetricCategoryMapping,
      where: m.group_id == ^group_id,
      select: max(m.display_order)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp upsert_groups(plan) do
    ids =
      Map.new(plan.groups, fn group ->
        row =
          case group.existing do
            nil ->
              {:ok, created} =
                MetricGroup.create(%{
                  name: group.name,
                  category_id: plan.category.id,
                  display_order: group.display_order
                })

              created

            existing ->
              {:ok, updated} = MetricGroup.update(existing, %{display_order: group.display_order})
              updated
          end

        {group.name, row.id}
      end)

    push_unlisted_groups_to_the_end(plan, ids)

    ids
  end

  # A group that survives because the spec neither lists nor dissolves it - Euler
  # and Morpho on stage - keeps its old display_order, which then collides with a
  # spec group's. Nothing enforces uniqueness, so the collision is invisible until
  # two groups render in an arbitrary order. Park the survivors after the spec's
  # own range instead.
  defp push_unlisted_groups_to_the_end(plan, ids) do
    listed = MapSet.new(Map.values(ids))
    offset = length(plan.groups)

    plan.category.id
    |> MetricGroup.list_by_category()
    |> Enum.reject(&MapSet.member?(listed, &1.id))
    |> Enum.with_index(offset + 1)
    |> Enum.each(fn {group, display_order} ->
      if group.display_order != display_order do
        {:ok, _} = MetricGroup.update(group, %{display_order: display_order})
      end
    end)
  end

  # display_order is per mapping row, so a metric in two groups gets an order in
  # each. Numbering follows the spec's metric order inside the group, and every
  # row of a spec-managed group is renumbered - not only the ones the spec lists -
  # so a surviving unrequested row cannot keep an order that collides with a
  # listed one (`topHoldersPercentOfTotalSupply` did exactly that).
  defp renumber_mappings(plan, group_ids) do
    spec_order =
      for group_spec <- plan.spec.groups,
          {metric, index} <- Enum.with_index(group_spec.metrics, 1),
          into: %{},
          do: {{group_spec.name, metric}, index}

    name_by_group_id = Map.new(group_ids, fn {name, id} -> {id, name} end)

    plan.category.id
    |> load_mappings()
    |> Enum.filter(&Map.has_key?(name_by_group_id, &1.group_id))
    |> Enum.group_by(& &1.group_id)
    |> Enum.each(fn {group_id, rows} ->
      group_name = name_by_group_id[group_id]

      rows
      # Listed metrics first, in spec order; anything else after, by id so the
      # result is stable across runs.
      |> Enum.sort_by(fn row ->
        {spec_order[{group_name, mapping_name(row)}] || 1_000_000, row.id}
      end)
      |> Enum.with_index(1)
      |> Enum.each(fn {row, display_order} ->
        if row.display_order != display_order do
          {:ok, _} = MetricCategoryMapping.update(row, %{display_order: display_order})
        end
      end)
    end)
  end

  defp log(message), do: IO.puts("[taxonomy] " <> message)
end

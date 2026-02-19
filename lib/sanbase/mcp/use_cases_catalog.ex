defmodule Sanbase.MCP.UseCasesCatalog do
  @moduledoc """
  Catalog of analytical use cases with execution steps.
  Each use case includes plain English instructions referencing specific MCP tools.
  """

  def all_use_cases do
    [
      identify_market_tops()
    ]
  end

  defp identify_market_tops do
    %{
      id: "identify_market_tops",
      title: "Identify Market Tops Using Santiment Metrics",
      description: """
      Multi-signal approach combining social volume, sentiment, network activity,
      and on-chain metrics to identify potential market tops. This framework
      emphasizes using multiple indicators together rather than relying on any
      single metric.
      """,
      category: "market_timing",
      difficulty: "intermediate",
      estimated_time: "5-10 minutes",
      applies_to: "Any crypto asset with sufficient data history",
      steps: """
      Step 1: Check for social volume spikes during rallies
      Use the fetch_metric_data tool with these parameters:
      - metric: "social_volume_total"
      - slugs: [your target asset, e.g., "bitcoin"]
      - time_period: "30d"
      - interval: "1d"

      Look for extreme spikes in social volume (3x or more above the 30-day baseline)
      that occur during price rallies. This is especially reliable for mid-cap and
      small-cap coins. Extreme social attention during rallies often marks local tops.

      Step 2: Analyze sentiment for overbought crowd conditions
      Use the fetch_metric_data tool to check positive sentiment:
      - metric: "sentiment_positive_total"
      - slugs: [your target asset]
      - time_period: "7d"
      - interval: "1d"

      When the crowd is overly bullish, it can indicate a top. Look for:
      - Positive sentiment representing > 70% of total mentions
      - This elevated sentiment sustained for 3+ consecutive days

      Optionally also fetch "sentiment_negative_total" and "sentiment_balance_total"
      for a more complete picture. Strongly positive sentiment balance (>+0.5)
      during rallies is a bearish signal.

      Step 3: Check for network activity vs. price behavior divergence
      Use the fetch_metric_data tool to check network activity:
      - metric: "daily_active_addresses"
      - slugs: [your target asset]
      - time_period: "30d"
      - interval: "1d"

      Compare the trend in daily active addresses with price movement. If price has
      risen 20% or more but daily active addresses remain flat or are declining,
      this divergence signals a potential top. Healthy rallies are supported by
      increasing on-chain activity.

      Optionally also check "network_growth" (new addresses) for additional confirmation.

      Step 4: Check MVRV ratio for overbought valuation
      Use the fetch_metric_data tool to check valuation:
      - metric: "mvrv_usd"
      - slugs: [your target asset]
      - time_period: "90d"
      - interval: "1d"

      MVRV (Market Value to Realized Value) ratio indicates whether holders are
      in profit. High MVRV suggests many holders are sitting on gains and may
      take profits. Thresholds vary by asset:
      - Bitcoin: MVRV > 2.5 indicates overbought (bull market: > 3.5)
      - Other assets: Research historical MVRV levels for the specific asset

      Step 5: Check Mean Dollar Invested Age for long-term holder distribution
      Use the fetch_metric_data tool to check coin age:
      - metric: "mean_dollar_invested_age"
      - slugs: [your target asset]
      - time_period: "180d"
      - interval: "1d"

      MDIA tracks how long funds have stayed in addresses. Rising MDIA indicates
      hodler accumulation, while dips suggest movement of previously idle coins.

      Every major Bitcoin top has been accompanied by a significant drop in MDIA
      as long-term holders distribute coins. Look for sharp drops (>10%) during
      price rallies. This is particularly relevant for Bitcoin and major assets
      with long history.
      """,
      interpretation: """
      ## How to Interpret Combined Signals

      This framework uses multiple indicators. Assess the overall picture:

      **Strong Top Signal (High Confidence)**
      When you observe 4-5 of these conditions together:
      - Social volume spike 3x+ baseline during rally
      - Positive sentiment > 70% sustained 3+ days
      - Network activity declining while price rises 20%+
      - MVRV > 2.5 (or asset-specific threshold)
      - MDIA drops > 10% during rally

      Action: Consider taking profits or tightening stop losses

      **Moderate Top Signal**
      When 2-3 bearish signals are present with mixed signals across categories.

      Action: Monitor closely, consider reducing position size

      **Weak/No Top Signal**
      When 0-1 bearish signals present and most metrics show healthy conditions.

      Action: Continue holding, no immediate concern

      ## Important Context
      - **Small/mid-cap coins**: Social volume spikes are more reliable indicators
      - **Large-cap coins (BTC, ETH)**: MDIA and network activity more important
      - **Bull markets**: Higher thresholds needed (MVRV > 3.5 for BTC)
      - **Bear markets**: Lower thresholds (MVRV > 1.5 may indicate local top)
      - **No single metric**: Always combine multiple data points for robust analysis

      ## Setting Up Alerts
      On Sanbase, you can subscribe to alerts for surges in social volume to catch
      potential corrections early. Use the Social Trends tool to visualize momentum.
      """,
      references: [
        %{
          title: "Getting started with Santiment",
          url: "https://academy.santiment.net/santiment-introduction/"
        },
        %{
          title: "Getting started for traders",
          url: "https://academy.santiment.net/for-traders/"
        },
        %{
          title: "Understanding Short-Term Market Trends",
          url:
            "https://academy.santiment.net/education-and-use-cases/understanding-short-term-market-trends/"
        },
        %{
          title: "Sentiment metrics",
          url: "https://academy.santiment.net/metrics/sentiment-metrics/"
        }
      ]
    }
  end
end

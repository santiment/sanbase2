# Santiment MCP Connector

Santiment's MCP (Model Context Protocol) connector gives Claude direct access to crypto market intelligence — on-chain metrics, social sentiment, trending narratives, and analyst insights — so you can research, validate, and analyze without leaving the conversation.

## Features

- **Metrics & Asset Discovery** — Browse 30+ metrics across 500+ crypto assets. Filter by asset, metric, or both.
- **Timeseries Data** — Fetch historical metric data (price, volume, market cap, active addresses, exchange flows, social volume, etc.) with configurable intervals and time ranges.
- **Asset Screening** — Filter and rank assets by any metric using threshold comparisons (greater than, less than) or percentage changes (up/down) with sorting and pagination.
- **Insights** — Discover and read full analyst insights published on Santiment, with tags, authors, and predictions.
- **Trending Stories** — See what narratives are driving crypto markets right now, with bullish/bearish sentiment breakdowns.
- **Combined Trends** — Unified view of trending words, stories, and AI-summarized social media discussions across the crypto space.

## Setup

### Claude.ai / Claude Desktop

1. Open Claude and navigate to the Connectors section.
2. Find **Santiment** and click Connect.
3. You'll be redirected to Santiment to authorize access via OAuth.
4. Log in (or create a free account at [app.santiment.net](https://app.santiment.net)) and approve the connection.
5. Start asking questions about any token, metric, or market condition.

### Claude Code

Add to your MCP configuration:

```json
{
  "mcpServers": {
    "santiment": {
      "type": "streamable-http",
      "url": "https://api.santiment.net/mcp"
    }
  }
}
```

## Authentication

The connector uses **OAuth 2.0 authorization code flow** with PKCE. When you first connect, you'll be prompted to log in to your Santiment account and authorize Claude to access data on your behalf.

- Access tokens are valid for 1 hour and automatically refresh.
- A free Santiment account provides access to core metrics and signals.
- Paid tiers unlock full on-chain depth and advanced metrics.

## Available Tools

| Tool | Description |
|------|-------------|
| **metrics_and_assets_discovery_tool** | Discover available metrics and crypto assets. Filter by slug, metric, or both. |
| **fetch_metric_data_tool** | Fetch timeseries data for a metric across one or more assets. |
| **assets_by_metric_tool** | Screen and rank assets by metric values or percentage changes. |
| **insight_discovery_tool** | Browse recently published Santiment analyst insights. |
| **fetch_insights_tool** | Read the full content of specific insights by ID. |
| **trending_stories_tool** | Get trending crypto stories with sentiment analysis. |
| **combined_trends_tool** | Unified view of trending words, stories, and AI-summarized discussions. |

## Usage Examples

### Example 1: Market Research for Content Creation

**Prompt:**
> "Give me a summary of BTC on-chain activity, exchange inflows/outflows, and social dominance for the past week — I'm writing a market thread for X."

**What happens:**
Claude uses `fetch_metric_data_tool` to pull `exchange_inflow_usd`, `exchange_outflow_usd`, `daily_active_addresses`, and `social_dominance_total` for Bitcoin over the last 7 days. It then synthesizes the data into a narrative with key data points highlighted — ready to turn into a thread.

### Example 2: Validating a Token's Hype

**Prompt:**
> "Is the current hype around Ethereum backed by real activity or is it just social noise?"

**What happens:**
Claude fetches `social_volume_total`, `sentiment_weighted_total`, `daily_active_addresses`, and `exchange_inflow_usd` for Ethereum over the last 14 days using `fetch_metric_data_tool`. It compares social buzz against on-chain fundamentals and gives you a clear read: is the excitement backed by real usage, or is retail just getting excited?

### Example 3: Screening for Top Movers

**Prompt:**
> "Find me the top 20 tokens whose price increased more than 25% in the last 7 days, sorted by biggest gainers first."

**What happens:**
Claude calls `assets_by_metric_tool` with `metric: "price_usd"`, `operator: "percent_up"`, `threshold: 25.0`, `from: "utc_now-7d"`, `to: "utc_now"`, `sort: "desc"`, `page_size: 20`. It returns a ranked list of the biggest gainers, which Claude can then analyze further by pulling additional metrics for any of them.

### Example 4: Thesis Validation with Divergence Detection

**Prompt:**
> "Pull Santiment exchange netflow data and social sentiment for [token] over the past 45 days. I'm looking for a divergence — price down but smart money accumulating. Confirm or kill my thesis."

**What happens:**
Claude fetches `exchange_inflow_usd`, `exchange_outflow_usd`, `price_usd`, and `sentiment_weighted_total` using `fetch_metric_data_tool`. It analyzes whether exchange outflows (accumulation signal) are elevated while sentiment remains bearish — a classic divergence pattern that can indicate institutional accumulation before a move.

### Example 5: What's Trending Right Now

**Prompt:**
> "What are the biggest crypto narratives trending in the last 6 hours?"

**What happens:**
Claude calls `combined_trends_tool` with `time_period: "6h"` to get trending stories and words with sentiment breakdowns and AI-generated summaries of social media discussions. You get a snapshot of what the crypto market is actually talking about — not just price action, but the narratives driving it.

## Supported Metrics

### Financial
`price_usd`, `marketcap_usd`, `volume_usd`, `price_btc`, `price_volatility_1d`, `fully_diluted_valuation_usd`

### On-Chain
`daily_active_addresses`, `transactions_count`, `transaction_volume`, `mvrv_usd`, `supply_on_exchanges`, `exchange_inflow_usd`, `exchange_outflow_usd`, `network_growth`

### Development
`dev_activity_1d`, `dev_activity_contributors_count_7d`

### Social
`social_volume_total`, `social_dominance_total`, `sentiment_weighted_total`, and source-specific variants for Twitter, Telegram, and Reddit.

For a full list, use the `metrics_and_assets_discovery_tool` with no parameters.

## Privacy

Santiment collects only the data necessary to serve your requests. No conversation content is stored. See our [Privacy Policy](https://santiment.net/privacy-policy/) for details.

## Support

- Email: [support@santiment.net](mailto:support@santiment.net)
- Website: [santiment.net](https://santiment.net)
- Discord: [Santiment Community](https://santiment.net/discord)

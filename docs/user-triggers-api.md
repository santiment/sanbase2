# Table of contents

- [Table of contents](#table-of-contents)
  - [Trigger structure](#trigger-structure)
    - [Settings fields](#settings-fields)
    - [Examples](#examples)
      - [Example settings structure for `trending_words`](#example-settings-structure-for-trending_words)
      - [Example settings structure for `price_volume_difference`](#example-settings-structure-for-price_volume_difference)
      - [Example settings structure for `signal_data`](#example-settings-structure-for-signal_data)
      - [Example settings structure for `wallet_movement`](#example-settings-structure-for-wallet_movement)
      - [Example settings structure for `wallet_usd_valuation`](#example-settings-structure-for-wallet_usd_valuation)
      - [Example settings structure for `metric_signal`](#example-settings-structure-for-metric_signal)
        - [Price data](#price-data)
        - [Social data](#social-data)
        - [On-chain data](#on-chain-data)
        - [Github data](#github-data)
        - [Intraday MVRV](#intraday-mvrv)
      - [Example settings structure for `daily_metric_signal`](#example-settings-structure-for-daily_metric_signal)
      - [Example settings structure for `screener_signal`](#example-settings-structure-for-screener_signal)
    - [Create trigger](#create-trigger)
    - [Get all triggers for current user](#get-all-triggers-for-current-user)
    - [Update trigger by id](#update-trigger-by-id)
    - [Remove trigger by id](#remove-trigger-by-id)
    - [Getting trigger by id](#getting-trigger-by-id)
    - [Getting all public triggers](#getting-all-public-triggers)
    - [Getting all public triggers for given user](#getting-all-public-triggers-for-given-user)
    - [Featured user triggers](#featured-user-triggers)
    - [API for alerts historical activity (user alerts timeline)](#api-for-alerts-historical-activity-user-alerts-timeline)
      - [Historical activity request](#historical-activity-request)
      - [Historical activity response](#historical-activity-response)
      - [Take activities newer than certain datetime](#take-activities-newer-than-certain-datetime)
      - [Take activities before certain datetime](#take-activities-before-certain-datetime)
    - [Historical trigger points](#historical-trigger-points)

## Trigger structure

These are the fields describing a trigger.

```elixir
    field(:settings, :map) # Each different trigger type has different settings. Described below.
    field(:title, :string) # Trigger title
    field(:description, :string) # Trigger description
    field(:is_public, :boolean, default: false) # Whether trigger is public or private
    field(:cooldown, :string, default: "24h") # After an alert is fired it can be again fired after `cooldown` time has passed. By default - `24h`
    field(:icon_url, :string) # Url of icon for the trigger
    field(:is_active, :boolean, default: true) # Whether trigger is active. By default - yes
    field(:is_repeating, :boolean, default: true) # Whether the alert will fire just one time or it will be working until manually turned off. By default - working until turned off.
```

### Settings fields

- **type** Defines the type of the trigger. Can be one of: `["trending_words", "price_volume_difference", "metric_signal", "daily_metric_signal", "wallet_movement", "signal_data"]`
- **target**: Slug or list of slugs or watchlist or ethereum addresses or list of ethereum addresses - `{"slug": "naga"} | {"slug": ["ethereum", "santiment"]} | {"watchlist_id": watchlsit_id} | {"eth_address": "0x123"} | {"eth_address": ["0x123", "0x234"]}`.
- **channel**: A channel where the alert is sent. Can be one of `"telegram" | "email" | "web_push" | {"webhook": <webhook_url>}` | `{"telegram_channel": "@<channel_name>"}` or a list of any combination. In case of telegram_channel, the bot must be an admin that has post messages priviliges.
- **time_window**: `1d`, `4w`, `1h` - Time string we use throughout the API for `interval`
- **operation** - A map describing the operation that triggers the alert. Check the examples.
- **threshold** - Float threshold used in `price_volume_difference`
- **trigger_time** - At what time of the day to fire the alert. It ISO8601 UTC time used only in `trending_words`, ex: `"12:00:00"`

### Examples

#### Example settings structure for `trending_words`

```json
// Send the list of top 10 currently trending words at 12:00 UTC time.
{
  "type": "trending_words",
  "channel": "telegram",
  "operation": {
    "send_at_predefined_time": true,
    "trigger_time": "12:00:00",
    "size": 10
  }
}
```

```json
// Send an alert if one project is trending. A project is trending if
// at least one of its ticker, name or slug is in the trending words
// The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "trending_project": true }
}
```

```json
// Send an alert if any of the projects is trending. A project is trending if
// at least one of its ticker, name or slug is in the trending words
// The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "slug": ["santiment", "bitcoin"] },
  "operation": { "trending_project": true }
}
```

```json
// Send an alert if any of the projects in a watchlist is trending. A project is trending if
// at least one of its ticker, name or slug is in the trending words
// The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "watchlist_id": 272 },
  "operation": { "trending_project": true }
}
```

```json
// Send an alert if a word is trending. The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "word": "gandalf" },
  "operation": { "trending_word": true }
}
```

```json
// Send an alert if any of the words is trending. The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "word": ["btc", "eth", "xrp"] },
  "operation": { "trending_word": true }
}
```

#### Example settings structure for `price_volume_difference`

```json
// The price and volume of santiment diverged.
{
  "type": "price_volume_difference",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "threshold": 0.002
}
```

#### Example settings structure for `signal_data`
```json
// Send an alert if there are any signals
{
  "type": "signal_data",
  "signal": "dai_mint",
  "target": {"slug": "mint-collateral-dai"},
  "channel": "telegram",
  "operation": {"above": 0}
}
```

```json
// Send an alert if there are any signals for the last day
{
  "type": "signal_data",
  "signal": "dai_mint",
  "target": {"slug": "mint-collateral-dai"},
  "channel": "telegram",
  "time_window": "1d",
  "operation": {"above": 0}
}
```

#### Example settings structure for `wallet_movement`

This alert is the successor of `eth_wallet`. It allows for a wider variety
of blockchains and operations.

The following blockchains are supported, identified by `infrastructure`:

- (ETH) Ethereum
- (BTC) Bitcoin
- (BCH) Bitcoin Cash
- (LTC) Litecoin
- (XRP) Ripple
- (BNB or BEP2) Binance Chain

When working with `infrastructure` BTC, BCH or LTC no additional parameter is needed
as there are no tokens on these blockchains.
When working with `infrastructure` ETH, EOS or BNB an additional parameter `slug` is needed to specify
the token.
When working with `infrastructure` XRP an additional `currency` parameter is needed.

Valid `slug`s are the slugs of the projects on sanbase.
Valid `currency`s are the specific names given on the ripple chain. In most of the cases
these are the tickers of the projects. Supported currencies are: `XRP`, `BTC`, `ETH`, etc.

```json
// The combined balance of all santiment's ethereum addresses decreased by 100
{
  "type": "wallet_movement",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "selector": { "infrastructure": "ETH", "currency": "ethereum" },
  "operation": { "amount_down": 100 }
}
```

```json
// The combined balance of all santiment's ethereum addresses increased by 100
{
  "type": "wallet_movement",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "selector": { "infrastructure": "ETH", "currency": "ethereum" },
  "operation": { "amount_up": 100 }
}
```

```json
// The bitcoin balance of the address px1234 is above 1000
{
  "type": "wallet_movement",
  "channel": "telegram",
  "target": { "address": "px1234" },
  "selector": { "infrastructure": "BTC" },
  "operation": { "above": 1000 }
}
```

```json
// The bitcoin cash balance of the address px1234 is below 500
{
  "type": "wallet_movement",
  "channel": "telegram",
  "target": { "address": "px1234" },
  "selector": { "infrastructure": "BCH" },
  "operation": { "below": 1000 }
}
```

```json
// The Litecoin balance of the address px1234 has increased by 10% compared to 1 day ago
{
  "type": "wallet_movement",
  "channel": "telegram",
  "target": { "address": "px1234" },
  "selector": { "infrastructure": "LTC" },
  "time_window": "1d",
  "operation": { "percent_up": 10 }
}
```

```json
// The EOS balance of the address px1234 has decreased by 50% compared to 1 day ago
{
  "type": "wallet_movement",
  "channel": "telegram",
  "target": { "address": "px1234" },
  "selector": { "infrastructure": "EOS", "slug": "eos" },
  "time_window": "1d",
  "operation": { "percent_down": 50 }
}
```

```json
// The BTC currency balance on the ripple chain of the address px1234
// has increased by 50% compared to 1 day ago and is above 1000
{
  "type": "wallet_movement",
  "channel": "telegram",
  "target": { "address": "px1234" },
  "selector": { "infrastructure": "XRP", "currency": "BTC" },
  "time_window": "1d",
  "operation": { "all_of": [{ "percent_up": 50 }, { "above": 1000 }] }
}
```

```json
// The BNB balance chain of the address px1234
// decreased by at least 100 compared to 1 day ago and is below 500
{
  "type": "wallet_movement",
  "channel": "telegram",
  "target": { "address": "px1234" },
  "selector": { "infrastructure": "BNB", "slug": "binance-coin" },
  "time_window": "1d",
  "operation": { "all_of": [{ "amount_down": 100 }, { "below": 500 }] }
}
```

#### Example settings structure for `wallet_usd_valuation`

This alert allows you to monitor the full USD valuation of an address over
time. The USD valuation of an address is defined as the combined USD value of
all the coins/tokens held by that address. When change is monitored, the price
of the tokens at different point in time is used.

The following blockchains are supported, identified by `infrastructure`:

- (ETH) Ethereum
- (BTC) Bitcoin
- (BCH) Bitcoin Cash
- (LTC) Litecoin
- (XRP) Ripple
- (BNB or BEP2) Binance Chain

When working with the alert, provide the `infrastructure` in the selector and the
address in the `target`
```json
// The USD valuation of the null address increased by $1 million in the past 24 hours
{
  "type": "wallet_usd_valuation",
  "channel": "telegram",
  "target": { "address": "0x0000000000000000000000000000000000000000" },
  "time_window": "1d",
  "selector": { "infrastructure": "ETH"},
  "operation": { "amount_up": 1000000 }
}
```

#### Example settings structure for `metric_signal`

Supported most metrics that are obtainable by the getMetric API and have a min interval at most 5 minutes. These metrics are:

All metrics support the `slug` target.
All `social_volume_*` metrics also support the `text` target.

##### Price data

- "price_usd"
- "price_btc"
- "volume_usd"
- "marketcap_usd"

##### Social data

- "community_messages_count_telegram"
- "community_messages_count_total"
- "social_dominance_reddit"
- "social_dominance_telegram"
- "social_dominance_total"
- "social_volume_reddit"
- "social_volume_twitter"
- "social_volume_bitcointalk"
- "social_volume_telegram"
- "social_volume_total"

##### On-chain data

- "transaction_volume"
- "exchange_balance"
- "exchange_inflow"
- "exchange_outflow"
- "age_destroyed"

##### Github data

- "dev_activity"
- "github_activity"

##### Intraday MVRV

These metrics are not available for all assets for which daily MVRV is available.
For full list check [here](<https://api.santiment.net/graphiql?variables=&query=%7B%0A%20%20getMetric(metric%3A%20%22mvrv_usd_intraday%22)%20%7B%0A%20%20%20%20metadata%20%7B%0A%20%20%20%20%20%20availableSlugs%0A%20%20%20%20%7D%0A%20%20%7D%0A%7D%0A>)

- "mvrv_usd_intraday"
- "mvrv_usd_intraday_10y"
- "mvrv_usd_intraday_5y"
- "mvrv_usd_intraday_3y"
- "mvrv_usd_intraday_2y"
- "mvrv_usd_intraday_365d"
- "mvrv_usd_intraday_180d"
- "mvrv_usd_intraday_90d"
- "mvrv_usd_intraday_60d"
- "mvrv_usd_intraday_30d"
- "mvrv_usd_intraday_7d"
- "mvrv_usd_intraday_1d"

```json
// The social volume (mentions) of a random word or any correct Lucene query is above 300
{
  "type": "metric_signal",
  "metric": "social_volume_total",
  "time_window": "1d",
  "channel": "telegram",
  "target": { "text": "buy OR sell OR dump" },
  "operation": { "above": 300 }
}
```

```json
// The transaction volume of Santiment's project is above 1,000,000
{
  "type": "metric_signal",
  "metric": "transaction_volume",
  "time_window": "1d",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "above": 1000000 }
}
```

```json
// The price of Santiment's tokens increased by 10% compared to 1 day ago
{
  "type": "metric_signal",
  "metric": "circulation_1d",
  "time_window": "1d",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "percent_up": 10 }
}
```

```json
// The Exchange Inflow of Santiment's project increased by 10% AND is above 10_000
{
  "type": "metric_signal",
  "metric": "exchange_inflow",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "all_of": [{ "percent_up": 10 }, { "above": 10000 }] }
}
```

```json
// The Exchange Outflow of Santiment's project increased by 10% OR is above 10_000
{
  "type": "metric_signal",
  "metric": "exchange_outflow",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "some_of": [{ "percent_up": 10 }, { "above": 10000 }] }
}
```

#### Example settings structure for `daily_metric_signal`

The `daily_metric_signal` works exactly as `metric_signal` (they reuse all their
internal logic) with the only difference that it is evaluated only once a day at
03:00 UTC and works on metrics with 1 day min_interval such as, but not only:

- mean_age
- mean_age_dollar_invested
- nvt
- withdrawal_transactions
- etc.


```json
// The Mean Age of Santiment' increased by 10% AND is above 100
{
  "type": "daily_metric_signal",
  "metric": "mean_age",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "all_of": [{ "percent_up": 10 }, { "above": 10000 }] }
}
```

```json
// The NVT of Ethereum project decreased by 15%
{
  "type": "daily_metric_signal",
  "metric": "exchange_outflow",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "percent_down": 15 }
}
```

#### Example settings structure for `screener_signal`

Receive a notification every `cooldown` the entering/exiting projects. Entering
projects are projects that previously did not satisfy the filters, but now do.
Exiting projects are projects that previously did satisfy the filters, but now
do not.

All metrics and fields (`"filters"`, `"orderBy"` and `"pagination"`) supported
in dynamic watchlsits and in the `allProjects` selector are supported in exactly
the same way with the same syntax in this signal

```json
// All stablecoin projects with DAA > 1000.
// `watchlistId` with an integer argument and `slugs` with a list of slugs
// are also supported for the base_projects argument
{
  "type": "screener_signal",
  "metric": "social_volume_total",
  "channel": "telegram",
  "operation": {
    "selector": {
      "base_projects": {"watchlistSlug": "stablecoins"},
      "filters": [
        {
          "metric": "daily_active_addresse",
          "dynamicFrom": "1d",
          "dynamicTo": "now",
          "aggregation": "last",
          "operation": "greater_than",
          "threshold": 500
        }
      ]
    }
  }
}
```

```json
// All projects with DAA > 500.
{
  "type": "screener_signal",
  "metric": "social_volume_total",
  "channel": "telegram",
  "operation": {
    "selector": {
      "filters": [
        {
          "metric": "daily_active_addresse",
          "dynamicFrom": "1d",
          "dynamicTo": "now",
          "aggregation": "last",
          "operation": "greater_than",
          "threshold": 500
        }
      ]
    }
  }
}
```

```json
// Follow projects entering/exiting a dynamic watchlist.
{
  "type": "screener_signal",
  "metric": "social_volume_total",
  "channel": "telegram",
  "operation": {
    "selector": { "watchlist_id": 12 }
  }
}
```

### Create trigger

```graphql
mutation {
  createTrigger(
    title: "test ceco"
    settings: "{\"channel\":\"telegram\",\"operation\":{\"percent_up\": 200},\"target\":{\"slug\": \"santiment\"},\"time_window\":\"30d\",\"type\":\"daily_active_addresses\"}"
  ) {
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Get all triggers for current user

```graphql
{
  currentUser {
    id
    triggers {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Update trigger by id

- If `settings` is updated all fields in settings must be provided.
- Trigger top-level ields can be updated - for ex: `isPublic`.

Update `settings` and `isPublic`.

```graphql
mutation {
  updateTrigger(
    id: 16
    isPublic: true
    settings: "{\"channel\":\"telegram\",\"operation\":{\"percent_up\": 250},\"target\":{\"slug\": \"santiment\"},\"time_window\":\"30d\",\"type\":\"daily_active_addresses\"}"
  ) {
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

Update only trigger top-level field `isPublic`.

```graphql
mutation {
  updateTrigger(id: 16, isPublic: true) {
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Remove trigger by id

```graphql
mutation {
  removeTrigger(id: 9) {
    trigger {
      id
    }
  }
}
```

### Getting trigger by id

```graphql
{
  getTriggerById(id: 16) {
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Getting all public triggers

```graphql
{
  allPublicTriggers {
    userId
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Getting all public triggers for given user

```graphql
{
  publicTriggersForUser(userId: 31) {
    userId
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Featured user triggers

```graphql
{
  featuredUserTriggers {
    trigger {
      title
      settings
    }
  }
}
```

### API for alerts historical activity (user alerts timeline)

#### Historical activity request

```graphql
{
  alertsHistoricalActivity(
    limit: 1
    cursor: { type: BEFORE, datetime: "2019-03-11T11:56:42.970284" }
  ) {
    cursor {
      before
      after
    }
    activity {
      payload
      triggeredAt
      trigger {
        id
        title
        description
      }
    }
  }
}
```

#### Historical activity response

````graphql
{
  "data": {
    "alertsHistoricalActivity": {
      "activity": [
        {
          "payload": {
            "all": "Trending words for: `2019-03-11`\n\n```\nWord    | Score\n------- | -------\ntheta   | 704\nxlm     | 425\nqlc     | 224\nnxs     | 210\nmining  | 207\nnano    | 196\nherpes  | 178\nxrp     | 178\nasic    | 152\ntattoos | 128\n```\n"
          },
          "triggeredAt": "2019-03-11T11:56:41.970284Z",
          "trigger": {
            "id": 5,
            "description": null,
            "title": "alabala",
            ...
          }
        }
      ],
      "cursor": {
        "after": "2019-03-11T11:56:41.970284Z",
        "before": "2019-03-11T11:56:41.970284Z"
      }
    }
  }
}
````

- `payload` is a json with key `slug` | `all` (when there is no specific slug) and value markdown message.

#### Take activities newer than certain datetime

```graphql
    alertsHistoricalActivity(
      limit:1,
      cursor:{
        type:AFTER,
        datetime:"2019-03-11T11:56:42.970284Z"
      }
    )
```

#### Take activities before certain datetime

```graphql
    alertsHistoricalActivity(
      limit:1,
      cursor:{
        type:BEFORE,
        datetime:"2019-03-11T11:56:42.970284Z"
      }
    )
```

### Historical trigger points

Takes currently filled settings and a chosen cooldown and calculates historical trigger points that can be used in a preview chart.

- Daily Active Addresses - 90 days of historical data. Minimal `time_window` is 2 days because intervals are 1 day each.
- Price - percent and absolute - 90 days of data. Minimal `time_window` is 2 hours because intervals are 1 hour each.
- PriceVolumeDifference - 180 days of data.

```graphql
{
  historicalTriggerPoints(
    cooldown: "2d"
    settings: "{\"operation\":{\"percent_up\": 200},\"target\":{\"slug\": \"naga\"},\"time_window\":\"30d\",\"type\":\"daily_active_addresses\"}"
  )
}
```

```graphql
{
  "data": {
    "historicalTriggerPoints": [
      {
        "active_addresses": 16,
        "datetime": "2018-12-18T00:00:00Z",
        "percent_change": 0,
        "price": 0.11502404063688457,
        "triggered?": false
      },
      {
        "active_addresses": 15,
        "datetime": "2018-12-19T00:00:00Z",
        "percent_change": 0,
        "price": 0.1267324715437431,
        "triggered?": false
      },
      {
        "active_addresses": 17,
        "datetime": "2018-12-20T00:00:00Z",
        "percent_change": 0,
        "price": 0.12995444389604163,
        "triggered?": false
      },
      ...
```

### Trigger structure

These are the fields describing a trigger. 

```elixir
    field(:settings, :map) # Each different trigger type has different settings. Described below.
    field(:title, :string) # Trigger title
    field(:description, :string) # Trigger description
    field(:is_public, :boolean, default: false) # Whether trigger is public or private 
    field(:cooldown, :string, default: "24h") # Cooldown fro trigger. By default - `24h`
    field(:icon_url, :string) # Url of icon for the trigger
    field(:active, :boolean, default: true) # Whether is active. By default - yes
    field(:repeating, :boolean, default: true) # Whether trigger will be executed after first time. By default - yes
```

#### settings fields

* `type` Defines the type of the trigger. Can be one of:
```
["daily_active_addresses", "price_absolute_change", "price_percent_change", "trending_words", "price_volume_difference"]
```

* `target` can be `slug`, `list of slugs`, `watchlist`

```
"target": "naga" | ["ethereum", "santiment"] | {"user_list": user_list_id}
```

* `channel`: 
```
"telegram" | "email" - currently only telegram is supported
```

* `time_window`
```
`1d`, `4w`, `1h` - time string we use throughout the API for `interval` 
```


#### example settings structure fo `daily_active_addresses`

```json
{
  "type": "daily_active_addresses",
  "target": ["santiment", "ethereum"],
  "channel": "telegram",
  "time_window": "30d",
  "percent_threshold": 5.0
}
```


``` graphql
mutation {
  createTrigger(
    settings: "{\"channel\":\"email\",\"percent_threshold\":400.0,\"repeating\":false,\"target\":\"santiment\",\"time_window\":\"1d\",\"type\":\"daily_active_addresses\"}"
  ) {
    id
    settings
    isPublic
  }
}
```

### API for signals historical activity a.k.a user signals timeline

#### Historical activity request

```graphql
{
    signalsHistoricalActivity(
      limit:1,
      cursor:{
        type:BEFORE,
        datetime:"2019-03-11T11:56:42.970284"
      }
    ) {
      cursor {
        before,
        after
      }
      activity {
        payload,
        triggeredAt,
        userTrigger {
          trigger {
            title,
            description
          }
        }
      }
    }
}
```

#### Historical activity response

```graphql
{
  "data": {
    "signalsHistoricalActivity": {
      "activity": [
        {
          "payload": {
            "all": "Trending words for: `2019-03-11`\n\n```\nWord    | Score\n------- | -------\ntheta   | 704\nxlm     | 425\nqlc     | 224\nnxs     | 210\nmining  | 207\nnano    | 196\nherpes  | 178\nxrp     | 178\nasic    | 152\ntattoos | 128\n```\nMore info: http://localhost:4000/sonar\n"
          },
          "triggeredAt": "2019-03-11T11:56:41.970284Z",
          "userTrigger": {
            "trigger": {
              "description": null,
              "title": "alabala"
            }
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
```
#### Take activities newer than certain datetime

```graphql
    signalsHistoricalActivity(
      limit:1,
      cursor:{
        type:AFTER,
        datetime:"2019-03-11T11:56:42.970284Z"
      }
    )
```

#### Take activities before certain datetime

```graphql
    signalsHistoricalActivity(
      limit:1,
      cursor:{
        type:BEFORE,
        datetime:"2019-03-11T11:56:42.970284Z"
      }
    )
```

### Historical trigger points

Currently we have it only

```graphql
 {
  historicalTriggerPoints(
    cooldown:"2d"
    settings: "{\"percent_threshold\":200.0,\"target\":\"naga\",\"time_window\":\"30d\",\"type\":\"daily_active_addresses\"}"
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

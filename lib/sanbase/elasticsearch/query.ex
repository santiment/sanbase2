defmodule Sanbase.Elasticsearch.Query do
  def telegram_channels_count(from, to) do
    from_unix = DateTime.to_unix(from, :millisecond)
    to_unix = DateTime.to_unix(to, :millisecond)

    ~s"""
    {
      "size": 0,
      "aggs": {
        "chat_titles": {
          "terms": {
            "field": "chat_title.keyword",
            "size": 999999
          }
        }
      },
      "query": {
        "bool": {
          "must": [
            {
              "range": {
                "timestamp": {
                  "gte": #{from_unix},
                  "lte": #{to_unix},
                  "format": "epoch_millis"
                }
              }
            }
          ]
        }
      }
    }
    """
  end

  def subreddits_count(from, to) do
    from_unix = DateTime.to_unix(from, :millisecond)
    to_unix = DateTime.to_unix(to, :millisecond)

    ~s"""
    {
      "size": 0,
      "aggs": {
        "subreddits": {
          "terms": {
            "field": "subreddit_name_prefixed.keyword",
            "size": 999999
          }
        }
      },
      "query": {
        "bool": {
          "must": [
            {
              "range": {
                "created_utc": {
                  "gte": #{from_unix},
                  "lte": #{to_unix},
                  "format": "epoch_millis"
                }
              }
            }
          ]
        }
      }
    }
    """
  end

  def documents_count_in_interval(from, to) do
    from_unix = DateTime.to_unix(from, :millisecond)
    to_unix = DateTime.to_unix(to, :millisecond)
    days_difference = Timex.diff(from, to) |> abs()

    ~s"""
    {
      "size": 0,
      "query": {
        "bool": {
          "should": [
            {
              "range": {
                "timestamp": {
                  "gte": #{from_unix},
                  "lte": #{to_unix},
                  "format": "epoch_millis"
                }
              }
            },
            {
              "range": {
                "created_utc": {
                  "gte": #{from_unix},
                  "lte": #{to_unix},
                  "format": "epoch_millis"
                }
              }
            }
          ]
        }
      }
    }
    """
  end
end

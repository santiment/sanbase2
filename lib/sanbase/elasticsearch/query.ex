defmodule Sanbase.Elasticsearch.Query do
  def telegram_channels_count(from, to) do
    from_unix = DateTime.to_unix(from, :millisecond)
    to_unix = DateTime.to_unix(to, :millisecond)

    ~s"""
    {
      "size": 0,
      "_source": {
        "excludes": []
      },
      "aggs": {
        "chat_titles": {
          "terms": {
            "field": "chat_title.keyword",
            "size": 999999
          }
        }
      },
      "stored_fields": [
        "chat_title.keyword"
      ],
      "script_fields": {},
      "docvalue_fields": [
        "timestamp"
      ],
      "query": {
        "bool": {
          "must": [
            {
              "match_all": {}
            },
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
      "_source": {
        "excludes": []
      },
      "aggs": {
        "subreddits": {
          "terms": {
            "field": "subreddit_name_prefixed.keyword",
            "size": 999999
          }
        }
      },
      "stored_fields": [
        "subreddit_name_prefixed.keyword"
      ],
      "script_fields": {},
      "docvalue_fields": [
        "created_utc"
      ],
      "query": {
        "bool": {
          "must": [
            {
              "match_all": {}
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
          ],
          "filter": [],
          "should": [],
          "must_not": []
        }
      }
    }
    """
  end
end

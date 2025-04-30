defmodule Sanbase.SocialData.TrendingStories do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Metric.SqlQuery.Helper, only: [to_unix_timestamp: 3, dt_to_unix: 2]

  @type slug :: String.t()
  @type interval :: String.t()

  @spec get_trending_stories(
          from :: DateTime.t(),
          to :: DateTime.t(),
          interval :: interval,
          size :: non_neg_integer,
          source :: atom()
        ) ::
          {:ok, map()} | {:error, String.t()}
  def get_trending_stories(from, to, interval, size, source \\ nil) do
    source = if is_nil(source), do: default_source(), else: to_string(source)

    query_struct = get_trending_stories_query(from, to, interval, size, source)

    Sanbase.ClickhouseRepo.query_reduce(query_struct, %{}, fn
      [
        dt,
        score,
        title,
        search_text,
        related_tokens,
        summary,
        bullish_ratio,
        bearish_ratio
      ],
      acc ->
        datetime = DateTime.from_unix!(dt)

        elem = %{
          score: score,
          title: title,
          search_text: search_text,
          related_tokens: related_tokens,
          summary: summary,
          bullish_ratio: bullish_ratio,
          bearish_ratio: bearish_ratio
        }

        Map.update(acc, datetime, [elem], fn words -> [elem | words] end)
    end)
  end

  defp get_trending_stories_query(from, to, interval, size, source) do
    sql = """
    SELECT
      t,
      score,
      title,
      search_text,
      related_tokens,
      summary,
      bullish_ratio,
      bearish_ratio
    FROM
    (
      SELECT
        #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
        dt,
        max(dt) OVER (PARTITION BY t) AS last_dt_in_group,
        score,
        title,
        search_text,
        related_tokens,
        summary,
        bullish_ratio,
        bearish_ratio
      FROM trending_stories_v2 FINAL
      WHERE
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        source = {{source}}
    )
    WHERE dt = last_dt_in_group
    ORDER BY t, score DESC
    LIMIT {{limit}} BY t
    """

    params = %{
      interval: str_to_sec(interval),
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      source: source,
      limit: size
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp default_source() do
    ch_url = System.get_env("CLICKHOUSE_URL") || ""

    if ch_url =~ "prduction", do: "twitter_crypto", else: "telegram"
  end
end

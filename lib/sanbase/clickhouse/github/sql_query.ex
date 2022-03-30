defmodule Sanbase.Clickhouse.Github.SqlQuery do
  @non_dev_events [
    "IssueCommentEvent",
    "IssuesEvent",
    "ForkEvent",
    "CommitCommentEvent",
    "FollowEvent",
    "ForkEvent",
    "DownloadEvent",
    "WatchEvent",
    "ProjectCardEvent",
    "ProjectColumnEvent",
    "ProjectEvent"
  ]

  @table "github_v2"

  def non_dev_events(), do: @non_dev_events

  def first_datetime_query(organization) when is_binary(organization) do
    query = """
    SELECT toUnixTimestamp(min(dt))
    FROM #{@table}
    owner = ?1 AND dt >= toDateTime('2005-01-01 00:00:00') AND dt <= now()
    """

    args = [organization]
    {query, args}
  end

  def last_datetime_computed_at_query(organization) when is_binary(organization) do
    query = """
    SELECT toUnixTimestamp(max(dt))
    FROM #{@table}
    PREWHERE owner = ?1 AND dt >= toDateTime('2005-01-01 00:00:00') AND dt <= now()
    """

    args = [organization]

    {query, args}
  end

  def dev_activity_contributors_count_query(organizations, from, to, interval) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = DateTime.to_unix(from)
    to_unix = Enum.min([DateTime.utc_now(), to], DateTime) |> DateTime.to_unix()
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval) |> max(1)

    query =
      """
      SELECT time, toUInt32(SUM(uniq_contributors)) AS value
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
          uniqExact(actor) AS uniq_contributors
        FROM #{@table}
        PREWHERE
          owner IN (?2) AND
          dt >= toDateTime(?3) AND
          dt < toDateTime(?4) AND
          event NOT IN (?5)
        GROUP BY time
      )
      GROUP BY time
      """
      |> wrap_timeseries_in_gap_filling_query(interval_pos: 1, from_datetime_pos: 3, span_pos: 6)

    args = [
      interval,
      organizations |> Enum.map(&String.downcase/1),
      from_unix,
      to_unix,
      @non_dev_events,
      span
    ]

    {query, args}
  end

  def github_activity_contributors_count_query(organizations, from, to, interval) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = DateTime.to_unix(from)
    to_unix = Enum.min([DateTime.utc_now(), to], DateTime) |> DateTime.to_unix()
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval) |> max(1)

    query =
      """
      SELECT time, toUInt32(SUM(uniq_contributors)) AS value
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
          uniqExact(actor) AS uniq_contributors
        FROM #{@table}
        PREWHERE
          owner IN (?2) AND
          dt >= toDateTime(?3) AND
          dt < toDateTime(?4)
        GROUP BY time
      )
      GROUP BY time
      """
      |> wrap_timeseries_in_gap_filling_query(interval_pos: 1, from_datetime_pos: 3, span_pos: 5)

    args = [
      interval,
      organizations |> Enum.map(&String.downcase/1),
      from_unix,
      to_unix,
      span
    ]

    {query, args}
  end

  def dev_activity_query(organizations, from, to, interval) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = DateTime.to_unix(from)
    to_unix = Enum.min([DateTime.utc_now(), to], DateTime) |> DateTime.to_unix()
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval) |> max(1)

    query =
      """
      SELECT time, SUM(events) AS value
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
          count(events) AS events
        FROM (
          SELECT any(event) AS events, dt
          FROM #{@table}
          PREWHERE
            owner IN (?2) AND
            dt >= toDateTime(?3) AND
            dt < toDateTime(?4) AND
            event NOT IN (?5)
          GROUP BY owner, repo, dt, event
        )
        GROUP BY time
      )
      GROUP BY time
      """
      |> wrap_timeseries_in_gap_filling_query(interval_pos: 1, from_datetime_pos: 3, span_pos: 6)

    args = [
      interval,
      organizations |> Enum.map(&String.downcase/1),
      from_unix,
      to_unix,
      @non_dev_events,
      span
    ]

    {query, args}
  end

  def github_activity_query(organizations, from, to, interval) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = DateTime.to_unix(from)
    to_unix = Enum.min([DateTime.utc_now(), to], DateTime) |> DateTime.to_unix()
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval) |> max(1)

    query =
      """
      SELECT time, SUM(events) AS value
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
          count(events) AS events
        FROM (
          SELECT any(event) AS events, dt
          FROM #{@table}
          PREWHERE
            owner IN (?2) AND
            dt >= toDateTime(?3) AND
            dt < toDateTime(?4)
          GROUP BY owner, repo, dt, event
        )
        GROUP BY time
      )
      GROUP BY time
      """
      |> wrap_timeseries_in_gap_filling_query(interval_pos: 1, from_datetime_pos: 3, span_pos: 5)

    args = [
      interval,
      organizations |> Enum.map(&String.downcase/1),
      from_unix,
      to_unix,
      span
    ]

    {query, args}
  end

  def total_github_activity_query(organizations, from, to) do
    query =
      """
      SELECT owner, toUInt64(COUNT(*)) AS value
      FROM(
        SELECT owner, COUNT(*)
        FROM #{@table}
        PREWHERE
          owner IN (?1) AND
          dt >= toDateTime(?2) AND
          dt < toDateTime(?3)
        GROUP BY owner, repo, dt, event
      )
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query(organizations_pos: 1)

    args = [
      organizations |> Enum.map(&String.downcase/1),
      DateTime.to_unix(from),
      DateTime.to_unix(to)
    ]

    {query, args}
  end

  def total_dev_activity_query(organizations, from, to) do
    query =
      """
      SELECT owner, toUInt64(COUNT(*)) AS value
      FROM(
        SELECT owner, COUNT(*)
        FROM #{@table}
        PREWHERE
          owner IN (?1) AND
          dt >= toDateTime(?2) AND
          dt <= toDateTime(?3) AND
          event NOT IN (?4)
        GROUP BY owner, repo, dt, event
      )
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query(organizations_pos: 1)

    args = [
      organizations |> Enum.map(&String.downcase/1),
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      @non_dev_events
    ]

    {query, args}
  end

  def total_dev_activity_contributors_count_query(organizations, from, to) do
    query =
      """
      SELECT owner, uniqExact(actor) AS value
      FROM #{@table}
      PREWHERE
        owner IN (?1) AND
        dt >= toDateTime(?2) AND
        dt <= toDateTime(?3) AND
        event NOT IN (?4)
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query(organizations_pos: 1)

    args = [
      organizations |> Enum.map(&String.downcase/1),
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      @non_dev_events
    ]

    {query, args}
  end

  def total_github_activity_contributors_count_query(organizations, from, to) do
    query =
      """
      SELECT owner, uniqExact(actor) AS value
      FROM #{@table}
      PREWHERE
        owner IN (?1) AND
        dt >= toDateTime(?2) AND
        dt <= toDateTime(?3)
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query(organizations_pos: 1)

    args = [
      organizations |> Enum.map(&String.downcase/1),
      DateTime.to_unix(from),
      DateTime.to_unix(to)
    ]

    {query, args}
  end

  defp wrap_aggregated_in_zero_filling_query(query, opts) do
    o_pos = Keyword.fetch!(opts, :organizations_pos)

    """
    SELECT owner, SUM(value)
    FROM (
      SELECT
      arrayJoin([?#{o_pos}]) AS owner,
      toUInt64(0) AS value

      UNION ALL

      #{query}
    )
    GROUP BY owner
    """
  end

  defp wrap_timeseries_in_gap_filling_query(query, opts) do
    i_pos = Keyword.fetch!(opts, :interval_pos)
    f_pos = Keyword.fetch!(opts, :from_datetime_pos)
    s_pos = Keyword.fetch!(opts, :span_pos)

    """
    SELECT time, SUM(value)
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(?#{f_pos} + number * ?#{i_pos}), ?#{i_pos}) * ?#{i_pos}) AS time,
        toUInt32(0) AS value
      FROM numbers(?#{s_pos})

      UNION ALL

      #{query}
    )
    GROUP BY time
    ORDER BY time
    """
  end
end

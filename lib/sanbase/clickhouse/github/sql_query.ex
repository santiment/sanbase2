defmodule Sanbase.Clickhouse.Github.SqlQuery do
  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      timerange_parameters: 3,
      to_unix_timestamp: 3,
      to_unix_timestamp_from_number: 2
    ]

  import Sanbase.DateTimeUtils, only: [maybe_str_to_sec: 1]

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

  def first_datetime_query(organization_or_organizations) do
    sql = """
    SELECT toUnixTimestamp(min(dt))
    FROM #{@table}
    PREWHERE
      owner IN ({{organizations}}) AND
      dt >= toDateTime('2005-01-01 00:00:00') AND
      dt <= now()
    """

    organizations = List.wrap(organization_or_organizations) |> Enum.map(&String.downcase/1)
    params = %{organizations: organizations}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def last_datetime_computed_at_query(organization_or_organizations) do
    sql = """
    SELECT toUnixTimestamp(max(dt))
    FROM #{@table}
    PREWHERE
      owner IN ({{organizations}}) AND
      dt >= toDateTime('2005-01-01 00:00:00')
      AND dt <= now()
    """

    organizations = List.wrap(organization_or_organizations) |> Enum.map(&String.downcase/1)
    params = %{organizations: organizations}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def dev_activity_contributors_count_query(organizations, from, to, interval) do
    {from, to, _interval, span} = timerange_parameters(from, to, interval)

    params = %{
      interval: maybe_str_to_sec(interval),
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: from,
      to: to,
      span: span,
      non_dev_events: @non_dev_events
    }

    # {to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
    sql =
      """
      SELECT time, toUInt32(SUM(uniq_contributors)) AS value
      FROM (
        SELECT
          #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
          uniqExact(actor) AS uniq_contributors
        FROM #{@table}
        PREWHERE
          owner IN ({{organizations}}) AND
          dt >= toDateTime({{from}}) AND
          dt < toDateTime({{to}}) AND
          event NOT IN ({{non_dev_events}})
        GROUP BY time
      )
      GROUP BY time
      """
      |> wrap_timeseries_in_gap_filling_query(interval)

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def github_activity_contributors_count_query(organizations, from, to, interval) do
    {from, to, _interval, span} = timerange_parameters(from, to, interval)

    params = %{
      interval: maybe_str_to_sec(interval),
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: from,
      to: to,
      span: span,
      non_dev_events: @non_dev_events
    }

    sql =
      """
      SELECT time, toUInt32(SUM(uniq_contributors)) AS value
      FROM (
        SELECT
          #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
          uniqExact(actor) AS uniq_contributors
        FROM #{@table}
        PREWHERE
          owner IN ({{organizations}}) AND
          dt >= toDateTime({{from}}) AND
          dt < toDateTime({{to}})
        GROUP BY time
      )
      GROUP BY time
      """
      |> wrap_timeseries_in_gap_filling_query(interval)

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def dev_activity_query(organizations, from, to, interval) do
    {from, to, _interval, span} = timerange_parameters(from, to, interval)

    params = %{
      interval: maybe_str_to_sec(interval),
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: from,
      to: to,
      span: span,
      non_dev_events: @non_dev_events
    }

    sql =
      """
      SELECT time, SUM(events) AS value
      FROM (
        SELECT
          #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
          count(events) AS events
        FROM (
          SELECT any(event) AS events, dt
          FROM #{@table}
          PREWHERE
            owner IN ({{organizations}}) AND
            dt >= toDateTime({{from}}) AND
            dt < toDateTime({{to}}) AND
            event NOT IN ({{non_dev_events}})
          GROUP BY owner, repo, dt, event
        )
        GROUP BY time
      )
      GROUP BY time
      """
      |> wrap_timeseries_in_gap_filling_query(interval)

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def github_activity_query(organizations, from, to, interval) do
    {from, to, _interval, span} = timerange_parameters(from, to, interval)

    params = %{
      interval: maybe_str_to_sec(interval),
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: from,
      to: to,
      span: span,
      non_dev_events: @non_dev_events
    }

    sql =
      """
      SELECT time, SUM(events) AS value
      FROM (
        SELECT
          #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
          count(events) AS events
        FROM (
          SELECT any(event) AS events, dt
          FROM #{@table}
          PREWHERE
            owner IN ({{organizations}}) AND
            dt >= toDateTime({{from}}) AND
            dt < toDateTime({{to}})
          GROUP BY owner, repo, dt, event
        )
        GROUP BY time
      )
      GROUP BY time
      """
      |> wrap_timeseries_in_gap_filling_query(interval)

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def total_github_activity_query(organizations, from, to) do
    sql =
      """
      SELECT owner, toUInt64(COUNT(*)) AS value
      FROM(
        SELECT owner, COUNT(*)
        FROM #{@table}
        PREWHERE
          owner IN ({{organizations}}) AND
          dt >= toDateTime({{from}}) AND
          dt < toDateTime({{to}})
        GROUP BY owner, repo, dt, event
      )
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query()

    params = [
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to)
    ]

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def total_dev_activity_query(organizations, from, to) do
    sql =
      """
      SELECT owner, toUInt64(COUNT(*)) AS value
      FROM(
        SELECT owner, COUNT(*)
        FROM #{@table}
        PREWHERE
          owner IN ({{organizations}}) AND
          dt >= toDateTime({{from}}) AND
          dt <= toDateTime({{to}}) AND
          event NOT IN ({{non_dev_events}})
        GROUP BY owner, repo, dt, event
      )
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query()

    params = %{
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      non_dev_events: @non_dev_events
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def total_dev_activity_contributors_count_query(organizations, from, to) do
    sql =
      """
      SELECT owner, uniqExact(actor) AS value
      FROM #{@table}
      PREWHERE
        owner IN ({{organizations}}) AND
        dt >= toDateTime({{from}}) AND
        dt <= toDateTime({{to}}) AND
        event NOT IN ({{non_dev_events}})
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query()

    params = %{
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      non_dev_events: @non_dev_events
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def total_github_activity_contributors_count_query(organizations, from, to) do
    sql =
      """
      SELECT owner, uniqExact(actor) AS value
      FROM #{@table}
      PREWHERE
        owner IN ({{organizations}}) AND
        dt >= toDateTime({{from}}) AND
        dt <= toDateTime({{to}})
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query()

    params = %{
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp wrap_aggregated_in_zero_filling_query(query) do
    """
    SELECT owner, SUM(value)
    FROM (
      SELECT
      arrayJoin([{{organizations}}]) AS owner,
      toUInt64(0) AS value

      UNION ALL

      #{query}
    )
    GROUP BY owner
    """
  end

  defp wrap_timeseries_in_gap_filling_query(query, interval) do
    """
    SELECT time, SUM(value)
    FROM (
      SELECT
        #{to_unix_timestamp_from_number(interval, from_argument_name: "from")} AS time,
        toUInt32(0) AS value
      FROM numbers({{span}})

      UNION ALL

      #{query}
    )
    GROUP BY time
    ORDER BY time
    """
  end
end

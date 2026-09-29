defmodule Sanbase.Clickhouse.Github.SqlQuery do
  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      timerange_parameters: 3,
      to_unix_timestamp: 3,
      to_unix_timestamp_from_number: 2
    ]

  import Sanbase.Utils.DateTime, only: [maybe_str_to_sec: 1]

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
  @bot_actor "endsWith(actor, '[bot]')"

  def non_dev_events(), do: @non_dev_events

  def first_datetime_query(organization_or_organizations) do
    sql = """
    SELECT toUnixTimestamp(min(dt))
    FROM #{@table}
    WHERE
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
    WHERE
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
        WHERE
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
        WHERE
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
          WHERE
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
          WHERE
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

  # Version 2.0 of dev_activity and github_activity. Compared to version 1.0:
  #   * the [bot] actors are ignored;
  #   * the same event stored twice, a few seconds apart, is counted once;
  #   * every event is weighted by min(1, cap / events of its (owner, repo, actor, day)),
  #     so automation running under a personal account cannot dominate the metric.
  @max_daily_actor_repo_events 100

  # GH Archive and the backfill store the same event 0-3 seconds apart. Events of
  # an (owner, repo, actor, event) at most this far apart form a run, and a run of
  # k events counts as ceil(k / 2).
  @pair_window_seconds 3

  # Runs can start before the first day of the time range.
  @lookback_seconds 600

  def max_daily_actor_repo_events(), do: @max_daily_actor_repo_events

  def dev_activity_v2_query(organizations, from, to, interval) do
    activity_v2_query(organizations, from, to, interval, dev_only?: true)
  end

  def github_activity_v2_query(organizations, from, to, interval) do
    activity_v2_query(organizations, from, to, interval, dev_only?: false)
  end

  # The upper bounds match the version 1.0 queries
  def total_dev_activity_v2_query(organizations, from, to) do
    total_activity_v2_query(organizations, from, to, dev_only?: true, to_operator: "<=")
  end

  def total_github_activity_v2_query(organizations, from, to) do
    total_activity_v2_query(organizations, from, to, dev_only?: false, to_operator: "<")
  end

  defp activity_v2_query(organizations, from, to, interval, opts) do
    {from, to, _interval, span} = timerange_parameters(from, to, interval)

    params = %{
      interval: maybe_str_to_sec(interval),
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: from,
      to: to,
      span: span,
      non_dev_events: @non_dev_events,
      max_daily_events: @max_daily_actor_repo_events
    }

    sql =
      activity_v2_timeseries_query(interval, opts)
      |> wrap_timeseries_in_gap_filling_query(interval)

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  # A day never spans two day-aligned intervals, so they need no window function.
  defp activity_v2_timeseries_query(interval, opts) do
    case day_aligned_interval?(interval) do
      true ->
        """
        SELECT
          #{to_unix_timestamp(interval, "toDateTime(day, 'UTC')", argument_name: "interval")} AS time,
          SUM(in_range_events * least(1, {{max_daily_events}} / day_events)) AS value
        FROM (
          SELECT
            group_key,
            toDate(dt, 'UTC') AS day,
            countIf(dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})) AS in_range_events,
            count() AS day_events
          FROM (
            #{deduplicated_events_query(opts)}
          )
          GROUP BY group_key, day
          HAVING in_range_events > 0
        )
        GROUP BY time
        """

      false ->
        """
        SELECT time, SUM(events * least(1, {{max_daily_events}} / day_events)) AS value
        FROM (
          SELECT
            time,
            in_range,
            events,
            sum(events) OVER (PARTITION BY group_key, day) AS day_events
          FROM (
            SELECT
              group_key,
              toDate(dt, 'UTC') AS day,
              #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
              dt >= toDateTime({{from}}) AND dt < toDateTime({{to}}) AS in_range,
              count() AS events
            FROM (
              #{deduplicated_events_query(opts)}
            )
            GROUP BY group_key, day, time, in_range
          )
        )
        WHERE in_range
        GROUP BY time
        """
    end
  end

  defp day_aligned_interval?("toStartOfHour"), do: false

  defp day_aligned_interval?(interval) do
    interval in Sanbase.Metric.SqlQuery.Helper.supported_interval_functions() or
      rem(Sanbase.Utils.DateTime.str_to_sec(interval), 86_400) == 0
  end

  defp total_activity_v2_query(organizations, from, to, opts) do
    to_operator = Keyword.fetch!(opts, :to_operator)

    # The zeros of the organizations without activity must be floats like the sums
    sql =
      """
      SELECT owner, SUM(in_range_events * least(1, {{max_daily_events}} / day_events)) AS value
      FROM (
        SELECT
          owner,
          countIf(dt >= toDateTime({{from}}) AND dt #{to_operator} toDateTime({{to}})) AS in_range_events,
          count() AS day_events
        FROM (
          #{deduplicated_events_query(opts)}
        )
        GROUP BY owner, group_key, toDate(dt, 'UTC')
      )
      GROUP BY owner
      """
      |> wrap_aggregated_in_zero_filling_query("toFloat64(0)")

    params = %{
      organizations: organizations |> Enum.map(&String.downcase/1),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      non_dev_events: @non_dev_events,
      max_daily_events: @max_daily_actor_repo_events
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  # Whole UTC days are selected, so an event's weight does not depend on the time
  # range. arrayFill carries each run's start position through the run and every
  # second event of the run is kept.
  defp deduplicated_events_query(opts) do
    dev_events_filter =
      if Keyword.fetch!(opts, :dev_only?),
        do: "AND event NOT IN ({{non_dev_events}})",
        else: ""

    """
    SELECT owner, toDateTime(kept_timestamp, 'UTC') AS dt, group_key
    FROM (
      SELECT
        owner,
        cityHash64(owner, repo, cityHash64(actor)) AS group_key,
        arraySort(groupUniqArray(toUInt32(dt))) AS timestamps,
        arrayEnumerate(timestamps) AS positions,
        arrayFill(
          x -> x > 0,
          arrayMap(
            (gap, i) -> if(i = 1 OR gap > #{@pair_window_seconds}, i, 0),
            arrayDifference(timestamps),
            positions
          )
        ) AS run_start_positions
      FROM #{@table}
      WHERE
        owner IN ({{organizations}}) AND
        dt >= toStartOfDay(toDateTime({{from}}, 'UTC')) - INTERVAL #{@lookback_seconds} SECOND AND
        dt < toStartOfDay(toDateTime({{to}}, 'UTC')) + INTERVAL 1 DAY
        AND NOT #{@bot_actor}
        #{dev_events_filter}
      GROUP BY owner, repo, actor, event
    )
    ARRAY JOIN
      arrayFilter((t, i, start) -> (i - start) % 2 = 0, timestamps, positions, run_start_positions) AS kept_timestamp
    """
  end

  def total_github_activity_query(organizations, from, to) do
    sql =
      """
      SELECT owner, toUInt64(COUNT(*)) AS value
      FROM(
        SELECT owner, COUNT(*)
        FROM #{@table}
        WHERE
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
        WHERE
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
      WHERE
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
      WHERE
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

  # A github event is identified by the (owner, repo, dt, event) tuple. The same
  # event can be present more than once in the table, so the activity is the
  # number of unique tuples and not the number of rows.
  @event_id "(owner, repo, dt, event)"
  @dev_event "event NOT IN ({{non_dev_events}})"

  # The single source of truth for the stats - the names and the order of the
  # columns selected by github_activity_stats_query/3.
  @stats_columns [
    dev_activity: "uniqExactIf(#{@event_id}, #{@dev_event})",
    github_activity: "uniqExact(#{@event_id})",
    dev_activity_contributors_count: "uniqExactIf(actor, #{@dev_event})",
    github_activity_contributors_count: "uniqExact(actor)",
    bot_dev_activity: "uniqExactIf(#{@event_id}, #{@bot_actor} AND #{@dev_event})",
    bot_github_activity: "uniqExactIf(#{@event_id}, #{@bot_actor})",
    bot_contributors_count: "uniqExactIf(actor, #{@bot_actor})"
  ]

  @doc ~s"""
  The names of the stats columns, in the order they are selected by
  github_activity_stats_query/3.
  """
  def stats_columns(), do: Keyword.keys(@stats_columns)

  @doc ~s"""
  Compute the stats for every slug in the `{github_organization, slug}` pairs.

  The organizations are mapped back to their slug, so that the rows of all
  organizations of a slug are aggregated together into a single result row.
  """
  def github_activity_stats_query(owner_slug_pairs, from, to) do
    {owners, slugs} = Enum.unzip(owner_slug_pairs)

    stats_select =
      Enum.map_join(@stats_columns, ",\n  ", fn {name, expr} ->
        "toUInt64(#{expr}) AS #{name}"
      end)

    sql = """
    SELECT
      transform(owner, {{owners}}, {{slugs}}, '') AS slug,
      #{stats_select}
    FROM #{@table}
    WHERE
      owner IN ({{owners}}) AND
      dt >= toDateTime({{from}}) AND
      dt <= toDateTime({{to}})
    GROUP BY slug
    """

    params = %{
      owners: owners |> Enum.map(&String.downcase/1),
      slugs: slugs,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      non_dev_events: @non_dev_events
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp wrap_aggregated_in_zero_filling_query(query, zero \\ "toUInt64(0)") do
    """
    SELECT owner, SUM(value)
    FROM (
      SELECT
      arrayJoin({{organizations}}) AS owner,
      #{zero} AS value

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

defmodule Sanbase.Clickhouse.Github do
  @moduledoc ~s"""
  Uses ClickHouse to work with github events.
  Allows to filter on particular events in the queries. Development activity can
  be more clearly calculated by excluding events releated to commenting, issues, forks, stars, etc.
  """

  @type t :: %__MODULE__{
          datetime: DateTime.t(),
          owner: String.t(),
          repo: String.t(),
          actor: String.t(),
          event: String.t()
        }

  use Ecto.Schema

  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

  require Logger
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

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

  @table "github"

  @primary_key false
  @timestamps_opts updated_at: false
  schema @table do
    field(:datetime, :utc_datetime, source: :dt, primary_key: true)
    field(:repo, :string, primary_key: true)
    field(:event, :string, primary_key: true)
    field(:owner, :string)
    field(:actor, :string)
  end

  @spec changeset(any(), any()) :: no_return
  def changeset(_, _) do
    raise "Cannot change github ClickHouse table!"
  end

  @doc ~s"""
  Return the number of all github events for a given organization and time period
  """
  @spec total_github_activity(list(String.t()), DateTime.t(), DateTime.t()) ::
          {:ok, float()}
          | {:error, String.t()}
  def total_github_activity([], _from, _to), do: {:ok, []}

  def total_github_activity(organizations, from, to) do
    {query, args} = total_github_activity_query(organizations, from, to)

    ClickhouseRepo.query_transform(query, args, fn [github_activity] ->
      github_activity |> Sanbase.Math.to_integer()
    end)
    |> maybe_unwrap_ok_value()
  end

  @doc ~s"""
  Return the number of github events, excluding the non-development related events (#{
    @non_dev_events
  }) for a given organization and time period
  """
  @spec total_dev_activity(list(String.t()), DateTime.t(), DateTime.t()) ::
          {:ok, list({String.t(), non_neg_integer()})} | {:error, String.t()}
  def total_dev_activity([], _from, _to), do: {:ok, []}

  def total_dev_activity(organizations, from, to) when length(organizations) > 20 do
    total_dev_activity =
      Enum.chunk_every(organizations, 20)
      |> Sanbase.Parallel.map(
        &total_dev_activity(&1, from, to),
        timeout: 25_000,
        max_concurrency: 8,
        ordered: false
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.flat_map(&elem(&1, 1))

    {:ok, total_dev_activity}
  end

  def total_dev_activity(organizations, from, to) do
    {query, args} = total_dev_activity_query(organizations, from, to)

    ClickhouseRepo.query_transform(query, args, fn [organization, dev_activity] ->
      {organization, dev_activity |> Sanbase.Math.to_integer()}
    end)
  end

  @doc ~s"""
  Get a timeseries with the pure development activity for a project.
  Pure development activity is all events excluding comments, issues, forks, stars, etc.
  """
  @spec dev_activity(
          list(String.t()),
          DateTime.t(),
          DateTime.t(),
          String.t(),
          String.t(),
          integer() | nil
        ) :: {:ok, list(t)} | {:error, String.t()}
  def dev_activity([], _, _, _, _, _), do: {:ok, []}

  def dev_activity(organizations, from, to, interval, transform, ma_base)
      when length(organizations) > 10 do
    dev_activity =
      Enum.chunk_every(organizations, 10)
      |> Sanbase.Parallel.map(
        &dev_activity(&1, from, to, interval, transform, ma_base),
        timeout: 25_000,
        max_concurrency: 8,
        ordered: false
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> Enum.zip()
      |> Enum.map(fn tuple ->
        [%{datetime: datetime} | _] = data = Tuple.to_list(tuple)

        combined_dev_activity =
          Enum.reduce(data, 0, fn
            %{activity: activity}, total -> total + activity
          end)

        %{datetime: datetime, activity: combined_dev_activity}
      end)

    {:ok, dev_activity}
  end

  def dev_activity(organizations, from, to, interval, "None", _) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    dev_activity_query(organizations, from, to, interval_sec)
    |> datetime_activity_execute()
  end

  def dev_activity(organizations, from, to, interval, "movingAverage", ma_base) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    dev_activity_query(organizations, from, to, interval_sec)
    |> datetime_activity_execute()
    |> case do
      {:ok, result} -> Sanbase.Math.simple_moving_average(result, ma_base, value_key: :activity)
      error -> error
    end
  end

  @doc ~s"""
  Get a timeseries with the pure development activity for a project.
  Pure development activity is all events excluding comments, issues, forks, stars, etc.
  """
  @spec github_activity(
          list(String.t()),
          DateTime.t(),
          DateTime.t(),
          String.t(),
          String.t(),
          non_neg_integer()
        ) :: {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
  def github_activity([], _, _, _, _, _), do: {:ok, []}

  def github_activity(organizations, from, to, interval, "None", _) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    github_activity_query(organizations, from, to, interval_sec)
    |> datetime_activity_execute()
  end

  def github_activity(organizations, from, to, interval, "movingAverage", ma_base) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    github_activity_query(organizations, from, to, interval_sec)
    |> datetime_activity_execute()
    |> case do
      {:ok, result} -> Sanbase.Math.simple_moving_average(result, ma_base, value_key: :activity)
      error -> error
    end
  end

  def first_datetime(organization) when is_binary(organization) do
    query = """
    SELECT toUnixTimestamp(min(dt))
    FROM #{@table}
    PREWHERE owner = ?1
    """

    args = [organization]

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      datetime |> DateTime.from_unix!()
    end)
    |> maybe_unwrap_ok_value()
  end

  def last_datetime_computed_at(organization) when is_binary(organization) do
    query = """
    SELECT toUnixTimestamp(max(dt))
    FROM #{@table}
    PREWHERE owner = ?1
    """

    args = [organization]

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      datetime |> DateTime.from_unix!()
    end)
    |> maybe_unwrap_ok_value()
  end

  def dev_activity_contributors_count(organizations, from, to, interval, "None", _) do
    do_dev_activity_contributors_count(organizations, from, to, interval)
  end

  def dev_activity_contributors_count(organizations, from, to, interval, "movingAverage", ma_base) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    do_dev_activity_contributors_count(organizations, from, to, interval)
    |> case do
      {:ok, result} ->
        Sanbase.Math.simple_moving_average(result, ma_base, value_key: :contributors_count)

      error ->
        error
    end
  end

  def github_activity_contributors_count(organizations, from, to, interval, "None", _) do
    do_github_activity_contributors_count(organizations, from, to, interval)
  end

  def github_activity_contributors_count(
        organizations,
        from,
        to,
        interval,
        "movingAverage",
        ma_base
      ) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    do_github_activity_contributors_count(organizations, from, to, interval)
    |> case do
      {:ok, result} ->
        Sanbase.Math.simple_moving_average(result, ma_base, value_key: :contributors_count)

      error ->
        error
    end
  end

  # Private functions

  defp do_dev_activity_contributors_count(organizations, from, to, interval) do
    {query, args} = dev_activity_contributors_count_query(organizations, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [datetime, contributors] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        contributors_count: contributors |> Sanbase.Math.to_integer()
      }
    end)
  end

  defp do_github_activity_contributors_count(organizations, from, to, interval) do
    {query, args} = github_activity_contributors_count_query(organizations, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [datetime, contributors] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        contributors_count: contributors |> Sanbase.Math.to_integer()
      }
    end)
  end

  defp datetime_activity_execute({query, args}) do
    ClickhouseRepo.query_transform(query, args, fn [datetime, events_count] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        activity: events_count |> Sanbase.Math.to_integer()
      }
    end)
  end

  defp dev_activity_contributors_count_query(organizations, from, to, interval) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval) |> max(1)

    query = """
    SELECT time, toUInt32(SUM(uniq_actors)) AS uniq_actors
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          0 AS uniq_actors
        FROM numbers(?2)

        UNION ALL

        SELECT toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time, uniq(actor) AS uniq_actors
        FROM #{@table}
        PREWHERE
          owner IN (?3) AND
          dt >= toDateTime(?4) AND
          dt < toDateTime(?5) AND
          event NOT IN (?6)
        GROUP BY time
      )
      GROUP BY time
      ORDER BY time
    """

    args = [
      interval,
      span,
      organizations,
      from_unix,
      to_unix,
      @non_dev_events
    ]

    {query, args}
  end

  defp github_activity_contributors_count_query(organizations, from, to, interval) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval) |> max(1)

    query = """
    SELECT time, toUInt32(SUM(uniq_actors)) AS uniq_actors
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          0 AS uniq_actors
        FROM numbers(?2)

        UNION ALL

        SELECT toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time, uniq(actor) AS uniq_actors
        FROM #{@table}
        PREWHERE
          owner IN (?3) AND
          dt >= toDateTime(?4) AND
          dt < toDateTime(?5)
        GROUP BY time
      )
      GROUP BY time
      ORDER BY time
    """

    args = [
      interval,
      span,
      organizations,
      from_unix,
      to_unix
    ]

    {query, args}
  end

  defp dev_activity_query(organizations, from, to, interval) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - from_unix, interval) |> max(1)

    query = """
    SELECT time, SUM(events) AS events_count
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          0 AS events
        FROM numbers(?2)

        UNION ALL

        SELECT toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time, count(events) AS events
          FROM (
            SELECT any(event) AS events, dt
            FROM #{@table}
            PREWHERE
              owner IN (?3)
            AND dt >= toDateTime(?4)
            AND dt < toDateTime(?5)
            AND event NOT IN (?6)
            GROUP BY owner, repo, dt, event
          )
          GROUP BY time
      )
      GROUP BY time
      ORDER BY time
    """

    args = [
      interval,
      span,
      organizations,
      from_unix,
      to_unix,
      @non_dev_events
    ]

    {query, args}
  end

  defp github_activity_query(organizations, from, to, interval) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - from_unix, interval) |> max(1)

    query = """
    SELECT time, SUM(events) AS events_count
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          0 AS events
        FROM numbers(?2)

        UNION ALL

        SELECT toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time, count(events) AS events
          FROM (
            SELECT any(event) AS events, dt
            FROM #{@table}
            PREWHERE
              owner IN (?3)
              AND dt >= toDateTime(?4)
              AND dt <= toDateTime(?5)
            GROUP BY owner, repo, dt, event
          )
          GROUP BY time
      )
      GROUP BY time
      ORDER BY time
    """

    args = [
      interval,
      span,
      organizations,
      from_unix,
      to_unix
    ]

    {query, args}
  end

  defp total_github_activity_query(organizations, from, to) do
    query = """
    SELECT toUInt64(COUNT(*)) FROM (
      SELECT COUNT(*)
      FROM #{@table}
      PREWHERE
        owner IN (?1) AND
        dt >= toDateTime(?2) AND
        dt <= toDateTime(?3)
      GROUP BY owner, repo, dt, event
    )
    """

    args = [
      organizations,
      DateTime.to_unix(from),
      DateTime.to_unix(to)
    ]

    {query, args}
  end

  defp total_dev_activity_query(organizations, from, to) do
    query = """
    SELECT owner, toUInt64(COUNT(*))
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

    args = [
      organizations,
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      @non_dev_events
    ]

    {query, args}
  end
end

defmodule Sanbase.Clickhouse.Github do
  @moduledoc ~s"""
  Uses ClickHouse to work with ETH transfers.
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

    case ClickhouseRepo.query_transform(query, args, fn [github_activity] ->
           github_activity |> String.to_integer()
         end) do
      {:ok, [result]} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
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
      |> Sanbase.Parallel.map(&total_dev_activity(&1, from, to),
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
      {organization, dev_activity |> String.to_integer()}
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
      |> Sanbase.Parallel.map(&dev_activity(&1, from, to, interval, transform, ma_base),
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
      {:ok, result} -> sma(result, ma_base)
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
      {:ok, result} -> sma(result, ma_base)
      error -> error
    end
  end

  def first_datetime(slug) do
    query = """
    SELECT min(dt) FROM #{@table} WHERE owner = ?1
    """

    args = [slug]

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      datetime |> Sanbase.DateTimeUtils.from_erl!()
    end)
    |> case do
      {:ok, [first_datetime]} -> {:ok, first_datetime}
      error -> error
    end
  end

  # Private functions

  defp datetime_activity_execute({query, args}) do
    ClickhouseRepo.query_transform(query, args, fn [datetime, events_count] ->
      %{
        datetime: datetime |> Sanbase.DateTimeUtils.from_erl!(),
        activity: events_count |> String.to_integer()
      }
    end)
  end

  defp dev_activity_query(organizations, from_datetime, to_datetime, interval) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT time, SUM(events) as events_count
      FROM (
        SELECT
          toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) as time,
          0 AS events
        FROM numbers(?2)

        UNION ALL

        SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, count(events) as events
          FROM (
            SELECT any(event) as events, dt
            FROM #{@table}
            PREWHERE owner IN (?3)
            AND dt >= toDateTime(?4)
            AND dt <= toDateTime(?5)
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
      from_datetime_unix,
      to_datetime_unix,
      @non_dev_events
    ]

    {query, args}
  end

  defp github_activity_query(organizations, from_datetime, to_datetime, interval) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT time, SUM(events) as events_count
      FROM (
        SELECT
          toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) as time,
          0 AS events
        FROM numbers(?2)

        UNION ALL

        SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, count(events) as events
          FROM (
            SELECT any(event) as events, dt
            FROM #{@table}
            PREWHERE owner IN (?3)
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
      from_datetime_unix,
      to_datetime_unix
    ]

    {query, args}
  end

  defp total_github_activity_query(organizations, from, to) do
    query = """
    SELECT COUNT(*) FROM (
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
    SELECT owner, COUNT(*)
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

  # Simple moving average of the github activity datapoints. Used to smooth the
  # noise created by the less amount of events created during the night and weekends
  defp sma(list, period) when is_list(list) and is_integer(period) and period > 0 do
    result =
      list
      |> Enum.chunk_every(period, 1, :discard)
      |> Enum.map(fn elems ->
        {datetime, activity} = average(elems)

        %{
          datetime: datetime,
          activity: Float.round(activity, 3)
        }
      end)

    {:ok, result}
  end

  defp average([]), do: nil

  defp average(l) when is_list(l) do
    values = Enum.map(l, fn %{activity: da} -> da end)
    %{datetime: datetime} = List.last(l)
    avg_activity = Sanbase.Math.average(values)

    {datetime, avg_activity}
  end
end

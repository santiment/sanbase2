defmodule Sanbase.Clickhouse.Github do
  @moduledoc ~s"""
  Uses ClickHouse to work with github events.
  Allows to filter on particular events in the queries. Development activity can
  be more clearly calculated by excluding events releated to commenting, issues, forks, stars, etc.

  ## Versions

  dev_activity/7, github_activity/7, total_dev_activity/4 and total_github_activity/4
  accept a `:version` option:

    * "1.0" (default) - the number of distinct (owner, repo, dt, event) events.
    * "2.0" - dev_activity counts only the pushes, pull requests, reviews and
      releases, excludes the bot actors (the [bot] and -bot ones and the known bot
      accounts like copilot), counts the same event stored twice a few seconds apart once,
      excludes the actor-days of automation running under a personal account (dev
      events in almost every hour of the day or too many dev events in a single
      hour), and a single actor contributes at most N (configurable) events per
      repository per day.
      The values are floats.

  The queries of every version live in Sanbase.Clickhouse.Github.SqlQuery and are
  named after the metric - `dev_activity_query` for 1.0, `dev_activity_v2_query`
  for 2.0. A new version needs its queries, a versioned_query/2 clause and an entry
  in the available versions of Sanbase.Clickhouse.Github.MetricAdapter.
  """

  @type t :: %{
          datetime: DateTime.t(),
          owner: String.t(),
          repo: String.t(),
          actor: String.t(),
          event: String.t()
        }

  import __MODULE__.SqlQuery

  import Sanbase.Utils.Transform,
    only: [maybe_unwrap_ok_value: 1, maybe_apply_function: 2]

  alias __MODULE__.SqlQuery
  alias Sanbase.ClickhouseRepo
  alias Sanbase.Math

  @doc ~s"""
  Return the number of all github events for a given organization and time period.

  Accepts the `:version` option, see the Versions section of the moduledoc.
  """
  @spec total_github_activity(list(String.t()), DateTime.t(), DateTime.t(), Keyword.t()) ::
          {:ok, %{optional(String.t()) => number()}}
          | {:error, String.t()}
  def total_github_activity(organizations, from, to, opts \\ []) do
    with {:ok, query, to_number} <- versioned_query(:total_github_activity, opts) do
      total_activity(query, to_number, organizations, from, to)
    end
  end

  @doc ~s"""
  Return the number of github events, excluding the non-development
  related events (#{non_dev_events()}) for a given organization and
  time period.

  Accepts the `:version` option, see the Versions section of the moduledoc.
  """
  @spec total_dev_activity(list(String.t()), DateTime.t(), DateTime.t(), Keyword.t()) ::
          {:ok, %{optional(String.t()) => number()}}
          | {:error, String.t()}
  def total_dev_activity(organizations, from, to, opts \\ []) do
    with {:ok, query, to_number} <- versioned_query(:total_dev_activity, opts) do
      total_activity(query, to_number, organizations, from, to)
    end
  end

  @doc ~s"""
  Return the number of total dev activity contributors, excluding those
  who only contributed to (#{non_dev_events()}) events for a given list
  of organizatinons and time period
  """
  @spec total_dev_activity_contributors_count(
          list(String.t()),
          DateTime.t(),
          DateTime.t()
        ) ::
          {:ok, %{optional(String.t()) => non_neg_integer()}}
          | {:error, String.t()}
  def total_dev_activity_contributors_count(organizations, from, to) do
    total_activity(
      :total_dev_activity_contributors_count_query,
      &Math.to_integer(&1, 0),
      organizations,
      from,
      to
    )
  end

  @doc ~s"""
  Return the number of total github activity contributors for a given list
  of organizatinons and time period
  """
  @spec total_github_activity_contributors_count(
          list(String.t()),
          DateTime.t(),
          DateTime.t()
        ) ::
          {:ok, %{optional(String.t()) => non_neg_integer()}}
          | {:error, String.t()}
  def total_github_activity_contributors_count(organizations, from, to) do
    total_activity(
      :total_github_activity_contributors_count_query,
      &Math.to_integer(&1, 0),
      organizations,
      from,
      to
    )
  end

  @doc ~s"""
  Get a timeseries with the pure development activity for a project.
  Pure development activity is all events excluding comments, issues, forks, stars, etc.

  Accepts the `:version` option, see the Versions section of the moduledoc.
  """
  @spec dev_activity(
          list(String.t()),
          DateTime.t(),
          DateTime.t(),
          String.t(),
          String.t(),
          nil | non_neg_integer(),
          Keyword.t()
        ) :: {:ok, list(t)} | {:error, String.t()}
  def dev_activity(organizations, from, to, interval, transform, ma_base, opts \\ []) do
    with {:ok, query, to_number} <- versioned_query(:dev_activity, opts) do
      activity_timeseries(
        query,
        to_number,
        organizations,
        from,
        to,
        interval,
        transform,
        ma_base
      )
    end
  end

  @doc ~s"""
  Get a timeseries with all github events for a project.

  Accepts the `:version` option, see the Versions section of the moduledoc.
  """
  @spec github_activity(
          list(String.t()),
          DateTime.t(),
          DateTime.t(),
          String.t(),
          String.t(),
          nil | non_neg_integer(),
          Keyword.t()
        ) :: {:ok, list(t)} | {:error, String.t()}
  def github_activity(organizations, from, to, interval, transform, ma_base, opts \\ []) do
    with {:ok, query, to_number} <- versioned_query(:github_activity, opts) do
      activity_timeseries(
        query,
        to_number,
        organizations,
        from,
        to,
        interval,
        transform,
        ma_base
      )
    end
  end

  @doc ~s"""
  Return aggregated github activity stats per slug for a given time period.

  The stats include the total dev/github activity and contributors count, as
  well as the same numbers computed only for bot accounts (actors whose name
  ends with `[bot]` or `-bot` and the known bot accounts like `copilot`).

  The input is a list of `{github_organization, slug}` pairs, so a slug with
  multiple organizations appears in multiple pairs. All organizations are
  queried at once and the rows are grouped by slug directly in ClickHouse.
  This way the contributors count of a project with multiple organizations is
  exact, which is not possible when per-organization results are combined
  outside the database.

  Slugs without any activity in the time period are not present in the result.
  """
  @spec github_activity_stats(list({String.t(), String.t()}), DateTime.t(), DateTime.t()) ::
          {:ok, list(map())} | {:error, String.t()}
  def github_activity_stats([], _from, _to), do: {:ok, []}

  def github_activity_stats(owner_slug_pairs, from, to) do
    query_struct = github_activity_stats_query(owner_slug_pairs, from, to)

    ClickhouseRepo.query_transform(query_struct, fn [slug | values] ->
      stats_columns()
      |> Enum.zip(Enum.map(values, &Math.to_integer(&1, 0)))
      |> Map.new()
      |> Map.put(:slug, slug)
    end)
  end

  @doc ~s"""
  Return a github_activity_stats/3 result row with all stats set to zero.
  """
  @spec empty_activity_stats(String.t()) :: map()
  def empty_activity_stats(slug) do
    stats_columns()
    |> Map.new(&{&1, 0})
    |> Map.put(:slug, slug)
  end

  def first_datetime(organization_or_organizations) do
    query_struct = first_datetime_query(organization_or_organizations)

    ClickhouseRepo.query_transform(query_struct, fn [timestamp] ->
      timestamp |> DateTime.from_unix!()
    end)
    |> maybe_unwrap_ok_value()
  end

  def last_datetime_computed_at(organization_or_organizations) do
    query_struct = last_datetime_computed_at_query(organization_or_organizations)

    ClickhouseRepo.query_transform(query_struct, fn [datetime] ->
      datetime |> DateTime.from_unix!()
    end)
    |> maybe_unwrap_ok_value()
  end

  def dev_activity_contributors_count([], _, _, _, _, _), do: {:ok, []}

  def dev_activity_contributors_count(
        organizations,
        from,
        to,
        interval,
        "None",
        _
      ) do
    do_dev_activity_contributors_count(organizations, from, to, interval)
  end

  def dev_activity_contributors_count(
        organizations,
        from,
        to,
        interval,
        "movingAverage",
        ma_base
      ) do
    interval_sec = Sanbase.Utils.DateTime.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    do_dev_activity_contributors_count(organizations, from, to, interval)
    |> maybe_apply_function(
      &Math.simple_moving_average(&1, ma_base, value_key: :contributors_count)
    )
  end

  def github_activity_contributors_count([], _, _, _, _, _), do: {:ok, []}

  def github_activity_contributors_count(
        organizations,
        from,
        to,
        interval,
        "None",
        _
      ) do
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
    interval_sec = Sanbase.Utils.DateTime.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    do_github_activity_contributors_count(organizations, from, to, interval)
    |> maybe_apply_function(
      &Math.simple_moving_average(&1, ma_base, value_key: :contributors_count)
    )
  end

  # Private functions

  # Run `fun` over 20-organization chunks in parallel and merge the
  # `{:ok, map}` results into one map. The request context is captured
  # here (transitional `current/0` read) and re-seeded in each worker so
  # ClickHouse privacy SETTINGS survive the process boundary.
  defp chunked_parallel_merge(organizations, fun) do
    ctx = Sanbase.RequestContext.current()

    organizations
    |> Enum.chunk_every(20)
    |> Sanbase.Parallel.map(
      fun,
      timeout: 25_000,
      max_concurrency: 8,
      ordered: false,
      request_context: ctx
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
    |> then(fn result -> {:ok, result} end)
  end

  # The name of the SqlQuery function of the metric and version, and the parser of
  # its values. Version 2.0 weights the events, so its values are floats.
  defp versioned_query(name, opts) do
    case Keyword.get(opts, :version) || Sanbase.Metric.default_version() do
      "1.0" ->
        {:ok, :"#{name}_query", &Math.to_integer(&1, 0)}

      "2.0" ->
        {:ok, :"#{name}_v2_query", &Math.to_float(&1, 0.0)}

      version ->
        {:error,
         "Github activity version #{version} is not supported. Supported versions: 1.0, 2.0"}
    end
  end

  defp total_activity(_query, _to_number, [], _from, _to), do: {:ok, %{}}

  defp total_activity(query, to_number, organizations, from, to)
       when length(organizations) > 20 do
    chunked_parallel_merge(organizations, &total_activity(query, to_number, &1, from, to))
  end

  defp total_activity(query, to_number, organizations, from, to) do
    query_struct = apply(SqlQuery, query, [organizations, from, to])

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [organization, value], acc ->
      Map.put(acc, organization, to_number.(value))
    end)
  end

  defp activity_timeseries(_query, _to_number, [], _, _, _, _, _), do: {:ok, []}

  # A failed chunk fails the whole request - a sum without some of the
  # organizations would be silently lower.
  defp activity_timeseries(
         query,
         to_number,
         organizations,
         from,
         to,
         interval,
         transform,
         ma_base
       )
       when length(organizations) > 10 do
    ctx = Sanbase.RequestContext.current()

    Enum.chunk_every(organizations, 10)
    |> Sanbase.Parallel.map(
      &activity_timeseries(query, to_number, &1, from, to, interval, transform, ma_base),
      timeout: 25_000,
      max_concurrency: 8,
      ordered: false,
      request_context: ctx
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, data}, {:ok, acc} -> {:cont, {:ok, [data | acc]}}
      {:error, _} = error, _acc -> {:halt, error}
    end)
    |> case do
      {:ok, chunks} -> {:ok, chunks |> Enum.zip() |> Enum.map(&combine_dev_activity/1)}
      {:error, _} = error -> error
    end
  end

  defp activity_timeseries(query, to_number, organizations, from, to, interval, "None", _) do
    apply(SqlQuery, query, [organizations, from, to, interval])
    |> datetime_activity_execute(to_number)
  end

  defp activity_timeseries(
         query,
         to_number,
         organizations,
         from,
         to,
         interval,
         "movingAverage",
         ma_base
       ) do
    interval_sec = Sanbase.Utils.DateTime.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    apply(SqlQuery, query, [organizations, from, to, interval])
    |> datetime_activity_execute(to_number)
    |> maybe_apply_function(&Math.simple_moving_average(&1, ma_base, value_key: :activity))
  end

  defp combine_dev_activity(tuple) do
    [%{datetime: datetime} | _] = data = Tuple.to_list(tuple)

    combined_dev_activity =
      Enum.reduce(data, 0, fn
        %{activity: activity}, total -> total + activity
      end)

    %{datetime: datetime, activity: combined_dev_activity}
  end

  defp do_dev_activity_contributors_count(organizations, from, to, interval) do
    query_struct = dev_activity_contributors_count_query(organizations, from, to, interval)

    ClickhouseRepo.query_transform(query_struct, fn [datetime, contributors] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        contributors_count: contributors |> Math.to_integer(0)
      }
    end)
  end

  defp do_github_activity_contributors_count(organizations, from, to, interval) do
    query_struct =
      github_activity_contributors_count_query(
        organizations,
        from,
        to,
        interval
      )

    ClickhouseRepo.query_transform(query_struct, fn [datetime, contributors] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        contributors_count: contributors |> Math.to_integer(0)
      }
    end)
  end

  defp datetime_activity_execute(query_struct, to_number) do
    ClickhouseRepo.query_transform(query_struct, fn [datetime, value] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        activity: to_number.(value)
      }
    end)
  end
end

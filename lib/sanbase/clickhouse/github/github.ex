defmodule Sanbase.Clickhouse.Github do
  @moduledoc ~s"""
  Uses ClickHouse to work with github events.
  Allows to filter on particular events in the queries. Development activity can
  be more clearly calculated by excluding events releated to commenting, issues, forks, stars, etc.
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

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Math

  @doc ~s"""
  Return the number of all github events for a given organization and time period
  """

  @spec total_github_activity(list(String.t()), DateTime.t(), DateTime.t()) ::
          {:ok, %{optional(String.t()) => non_neg_integer()}}
          | {:error, String.t()}
  def total_github_activity([], _from, _to), do: {:ok, %{}}

  def total_github_activity(organizations, from, to)
      when length(organizations) > 20 do
    chunked_parallel_merge(organizations, &total_github_activity(&1, from, to))
  end

  def total_github_activity(organizations, from, to) do
    query_struct = total_github_activity_query(organizations, from, to)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [
                                                        organization,
                                                        github_activity
                                                      ],
                                                      acc ->
      Map.put(acc, organization, github_activity |> Math.to_integer(0))
    end)
  end

  @doc ~s"""
  Return the number of github events, excluding the non-development
  related events (#{non_dev_events()}) for a given organization and
  time period
  """
  @spec total_dev_activity(list(String.t()), DateTime.t(), DateTime.t()) ::
          {:ok, %{optional(String.t()) => non_neg_integer()}}
          | {:error, String.t()}
  def total_dev_activity([], _from, _to), do: {:ok, %{}}

  def total_dev_activity(organizations, from, to)
      when length(organizations) > 20 do
    chunked_parallel_merge(organizations, &total_dev_activity(&1, from, to))
  end

  def total_dev_activity(organizations, from, to) do
    query_struct = total_dev_activity_query(organizations, from, to)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [
                                                        organization,
                                                        dev_activity
                                                      ],
                                                      acc ->
      Map.put(acc, organization, dev_activity |> Math.to_integer(0))
    end)
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
  def total_dev_activity_contributors_count([], _from, _to), do: {:ok, %{}}

  def total_dev_activity_contributors_count(organizations, from, to)
      when length(organizations) > 20 do
    chunked_parallel_merge(organizations, &total_dev_activity_contributors_count(&1, from, to))
  end

  def total_dev_activity_contributors_count(organizations, from, to) do
    query_struct = total_dev_activity_contributors_count_query(organizations, from, to)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [
                                                        organization,
                                                        dev_activity
                                                      ],
                                                      acc ->
      Map.put(acc, organization, dev_activity |> Math.to_integer(0))
    end)
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
  def total_github_activity_contributors_count([], _from, _to), do: {:ok, %{}}

  def total_github_activity_contributors_count(organizations, from, to)
      when length(organizations) > 20 do
    chunked_parallel_merge(organizations, &total_github_activity_contributors_count(&1, from, to))
  end

  def total_github_activity_contributors_count(organizations, from, to) do
    query_struct = total_github_activity_contributors_count_query(organizations, from, to)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [
                                                        organization,
                                                        dev_activity
                                                      ],
                                                      acc ->
      Map.put(acc, organization, dev_activity |> Math.to_integer(0))
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
          nil | non_neg_integer()
        ) :: {:ok, list(t)} | {:error, String.t()}
  def dev_activity(organizations, from, to, interval, transform, moving_average_base)
  def dev_activity([], _, _, _, _, _), do: {:ok, []}

  def dev_activity(organizations, from, to, interval, transform, ma_base)
      when length(organizations) > 10 do
    ctx = Sanbase.RequestContext.current()

    Enum.chunk_every(organizations, 10)
    |> Sanbase.Parallel.map(
      &dev_activity(&1, from, to, interval, transform, ma_base),
      timeout: 25_000,
      max_concurrency: 8,
      ordered: false,
      request_context: ctx
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
    |> Enum.zip()
    |> Enum.map(&combine_dev_activity/1)
    |> then(fn result -> {:ok, result} end)
  end

  def dev_activity(organizations, from, to, interval, "None", _) do
    dev_activity_query(organizations, from, to, interval)
    |> datetime_activity_execute()
  end

  def dev_activity(organizations, from, to, interval, "movingAverage", ma_base) do
    interval_sec = Sanbase.Utils.DateTime.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    dev_activity_query(organizations, from, to, interval)
    |> datetime_activity_execute()
    |> maybe_apply_function(&Math.simple_moving_average(&1, ma_base, value_key: :activity))
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
          nil | non_neg_integer()
        ) :: {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
  def github_activity(organizations, from, to, interval, transform, moving_average_base)
  def github_activity([], _, _, _, _, _), do: {:ok, []}

  def github_activity(organizations, from, to, interval, "None", _) do
    github_activity_query(organizations, from, to, interval)
    |> datetime_activity_execute()
  end

  def github_activity(
        organizations,
        from,
        to,
        interval,
        "movingAverage",
        ma_base
      ) do
    interval_sec = Sanbase.Utils.DateTime.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    github_activity_query(organizations, from, to, interval)
    |> datetime_activity_execute()
    |> maybe_apply_function(&Math.simple_moving_average(&1, ma_base, value_key: :activity))
  end

  @doc ~s"""
  Return aggregated github activity stats per slug for a given time period.

  The stats include the total dev/github activity and contributors count,
  as well as the same numbers computed only for bot accounts (actors whose
  name ends with `[bot]`).

  The organizations of all projects are queried at once and the results are
  grouped by slug directly in ClickHouse. This way the contributors count of
  projects with multiple github organizations is computed exactly, which is
  not possible if the per-organization results are combined outside the
  database.

  The input is a list of `{github_organization, slug}` pairs. An organization
  is mapped back to the slug it belongs to, so a slug with multiple
  organizations appears in multiple pairs. Slugs without any activity in the
  time period are not present in the result.
  """
  @spec github_activity_stats(
          list({String.t(), String.t()}),
          DateTime.t(),
          DateTime.t()
        ) :: {:ok, list(map())} | {:error, String.t()}
  def github_activity_stats([], _from, _to), do: {:ok, []}

  def github_activity_stats(owner_slug_pairs, from, to) do
    query_struct = github_activity_stats_query(owner_slug_pairs, from, to)

    ClickhouseRepo.query_transform(
      query_struct,
      fn [slug | values] ->
        [
          dev_activity,
          github_activity,
          dev_activity_contributors_count,
          github_activity_contributors_count,
          bot_dev_activity,
          bot_github_activity,
          bot_contributors_count
        ] = Enum.map(values, &Math.to_integer(&1, 0))

        %{
          slug: slug,
          dev_activity: dev_activity,
          github_activity: github_activity,
          dev_activity_contributors_count: dev_activity_contributors_count,
          github_activity_contributors_count: github_activity_contributors_count,
          bot_dev_activity: bot_dev_activity,
          bot_github_activity: bot_github_activity,
          bot_contributors_count: bot_contributors_count
        }
      end
    )
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

  defp datetime_activity_execute(query_struct) do
    ClickhouseRepo.query_transform(query_struct, fn [datetime, value] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        activity: value |> Math.to_integer(0)
      }
    end)
  end
end

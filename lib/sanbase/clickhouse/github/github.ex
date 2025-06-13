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

  alias Sanbase.ChRepo
  alias Sanbase.Math

  require Logger

  @doc ~s"""
  Return the number of all github events for a given organization and time period
  """

  @spec total_github_activity(list(String.t()), DateTime.t(), DateTime.t()) ::
          {:ok, %{optional(String.t()) => non_neg_integer()}}
          | {:error, String.t()}
  def total_github_activity([], _from, _to), do: {:ok, %{}}

  def total_github_activity(organizations, from, to)
      when length(organizations) > 20 do
    Enum.chunk_every(organizations, 20)
    |> Sanbase.Parallel.map(
      &total_github_activity(&1, from, to),
      timeout: 25_000,
      max_concurrency: 8,
      ordered: false
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
    |> then(fn result -> {:ok, result} end)
  end

  def total_github_activity(organizations, from, to) do
    query_struct = total_github_activity_query(organizations, from, to)

    ChRepo.query_reduce(query_struct, %{}, fn [
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
    Enum.chunk_every(organizations, 20)
    |> Sanbase.Parallel.map(
      &total_dev_activity(&1, from, to),
      timeout: 25_000,
      max_concurrency: 8,
      ordered: false
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
    |> then(fn result -> {:ok, result} end)
  end

  def total_dev_activity(organizations, from, to) do
    query_struct = total_dev_activity_query(organizations, from, to)

    ChRepo.query_reduce(query_struct, %{}, fn [
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
    Enum.chunk_every(organizations, 20)
    |> Sanbase.Parallel.map(
      &total_dev_activity_contributors_count(&1, from, to),
      timeout: 25_000,
      max_concurrency: 8,
      ordered: false
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
    |> then(fn result -> {:ok, result} end)
  end

  def total_dev_activity_contributors_count(organizations, from, to) do
    query_struct = total_dev_activity_contributors_count_query(organizations, from, to)

    ChRepo.query_reduce(query_struct, %{}, fn [
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
    Enum.chunk_every(organizations, 20)
    |> Sanbase.Parallel.map(
      &total_github_activity_contributors_count(&1, from, to),
      timeout: 25_000,
      max_concurrency: 8,
      ordered: false
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
    |> then(fn result -> {:ok, result} end)
  end

  def total_github_activity_contributors_count(organizations, from, to) do
    query_struct = total_github_activity_contributors_count_query(organizations, from, to)

    ChRepo.query_reduce(query_struct, %{}, fn [
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
    |> Enum.map(&combine_dev_activity/1)
    |> then(fn result -> {:ok, result} end)
  end

  def dev_activity(organizations, from, to, interval, "None", _) do
    dev_activity_query(organizations, from, to, interval)
    |> datetime_activity_execute()
  end

  def dev_activity(organizations, from, to, interval, "movingAverage", ma_base) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
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
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    github_activity_query(organizations, from, to, interval)
    |> datetime_activity_execute()
    |> maybe_apply_function(&Math.simple_moving_average(&1, ma_base, value_key: :activity))
  end

  def first_datetime(organization_or_organizations) do
    query_struct = first_datetime_query(organization_or_organizations)

    ChRepo.query_transform(query_struct, fn [timestamp] ->
      timestamp |> DateTime.from_unix!()
    end)
    |> maybe_unwrap_ok_value()
  end

  def last_datetime_computed_at(organization_or_organizations) do
    query_struct = last_datetime_computed_at_query(organization_or_organizations)

    ChRepo.query_transform(query_struct, fn [datetime] ->
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
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
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
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -((ma_base - 1) * interval_sec))

    do_github_activity_contributors_count(organizations, from, to, interval)
    |> maybe_apply_function(
      &Math.simple_moving_average(&1, ma_base, value_key: :contributors_count)
    )
  end

  # Private functions

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

    ChRepo.query_transform(query_struct, fn [datetime, contributors] ->
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

    ChRepo.query_transform(query_struct, fn [datetime, contributors] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        contributors_count: contributors |> Math.to_integer(0)
      }
    end)
  end

  defp datetime_activity_execute(query_struct) do
    ChRepo.query_transform(query_struct, fn [datetime, value] ->
      %{
        datetime: datetime |> DateTime.from_unix!(),
        activity: value |> Math.to_integer(0)
      }
    end)
  end
end

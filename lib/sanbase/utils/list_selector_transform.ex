defmodule Sanbase.Utils.ListSelector.Transform do
  @moduledoc false
  import Sanbase.DateTimeUtils

  def args_to_filters_combinator(args) do
    (get_in(args, [:selector, :filters_combinator]) || "and")
    |> to_string()
    |> String.downcase()
  end

  def args_to_base_projects(args) do
    case get_in(args, [:selector, :base_projects]) do
      nil -> :all
      data -> data
    end
  end

  def args_to_filters(args) do
    (get_in(args, [:selector, :filters]) || [])
    |> Enum.map(&transform_from_to/1)
    |> Enum.map(&update_dynamic_datetimes/1)
    |> Enum.map(&atomize_values/1)
  end

  def args_to_order_by(args) do
    args
    |> get_in([:selector, :order_by])
    |> transform_from_to()
    |> update_dynamic_datetimes()
    |> maybe_shift_to_datetime()
    |> atomize_values()
  end

  def args_to_pagination(args) do
    get_in(args, [:selector, :pagination])
  end

  def atomize_values(nil), do: nil

  def atomize_values(%{args: args} = map) do
    %{map | args: atomize_values(args)}
  end

  def atomize_values(map) when is_map(map) do
    {to_atomize, rest} = Map.split(map, [:operator, :aggregation, :direction])

    to_atomize
    |> Map.new(fn {k, v} ->
      v = if is_binary(v), do: String.to_existing_atom(v), else: v
      {k, v}
    end)
    |> Map.merge(rest)
  end

  def atomize_values(data), do: data

  def transform_from_to(%{from: %DateTime{}, to: %DateTime{}} = map), do: map

  def transform_from_to(%{from: "utc_now" <> _ = from, to: "utc_now" <> _ = to} = map) do
    %{
      map
      | from: from |> utc_now_string_to_datetime!() |> round_datetime(rounding: :up),
        to: to |> utc_now_string_to_datetime!() |> round_datetime(rounding: :up)
    }
  end

  def transform_from_to(%{from: "utc_now" <> _}), do: {:error, "Cannot use dynamic 'from' without dynamic 'to'"}

  def transform_from_to(%{to: "utc_now" <> _}), do: {:error, "Cannot use dynamic 'to' without dynamic 'from'"}

  def transform_from_to(%{from: from, to: to} = map) when is_binary(from) and is_binary(to) do
    %{
      map
      | from: from |> from_iso8601!() |> round_datetime(rounding: :up),
        to: to |> from_iso8601!() |> round_datetime(rounding: :up)
    }
  end

  def transform_from_to(%{args: %{} = args} = map) do
    %{map | args: transform_from_to(args)}
  end

  def transform_from_to(map), do: map

  def update_dynamic_datetimes(nil), do: nil

  def update_dynamic_datetimes(%{args: args} = filter) do
    case update_dynamic_datetimes(args) do
      %{} = updated_args ->
        %{filter | args: updated_args}

      {:error, error} ->
        {:error, error}
    end
  end

  def update_dynamic_datetimes(%{} = args) do
    dynamic_from = Map.get(args, :dynamic_from)
    dynamic_to = Map.get(args, :dynamic_to)

    case {dynamic_from, dynamic_to} do
      {nil, nil} ->
        args

      {nil, _} ->
        {:error, "Cannot use 'dynamic_to' without 'dynamic_from'."}

      {_, nil} ->
        {:error, "Cannot use 'dynamic_from' without 'dynamic_to'."}

      _ ->
        now = DateTime.utc_now()
        shift_to_by = if dynamic_to == "now", do: 0, else: str_to_sec(dynamic_to)

        from = Timex.shift(now, seconds: -str_to_sec(dynamic_from))
        to = Timex.shift(now, seconds: -shift_to_by)

        args
        |> Map.put(:from, round_datetime(from, rounding: :up))
        |> Map.put(:to, round_datetime(to, rounding: :up))
    end
  end

  def update_dynamic_datetimes(filter), do: filter

  def maybe_shift_to_datetime(%{include_incomplete_data: true} = args), do: args

  def maybe_shift_to_datetime(%{to: to, metric: metric} = args) do
    with {:ok, %{has_incomplete_data: true}} <- Sanbase.Metric.metadata(metric),
         start_of_day = Timex.beginning_of_day(DateTime.utc_now()),
         comp when comp != :lt <- DateTime.compare(to, start_of_day) do
      shifted_to = Timex.shift(start_of_day, microseconds: -1)
      %{args | to: shifted_to}
    else
      _ -> args
    end
  end

  def maybe_shift_to_datetime(args), do: args
end

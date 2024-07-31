defmodule Sanbase.Project.ListSelector.Transform do
  import Sanbase.DateTimeUtils
  import Sanbase.Utils.ListSelector.Transform, only: [atomize_values: 1]

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
    get_in(args, [:selector, :order_by])
    |> transform_from_to()
    |> update_dynamic_datetimes()
    |> atomize_values()
  end

  def args_to_pagination(args) do
    get_in(args, [:selector, :pagination])
  end

  def transform_from_to(%{from: from, to: to} = map) do
    %{
      map
      | from:
          if(is_binary(from),
            do: from_iso8601!(from) |> round_datetime(rounding: :up),
            else: from
          ),
        to: if(is_binary(to), do: from_iso8601!(to) |> round_datetime(rounding: :up), else: to)
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

  def update_dynamic_datetimes(%{} = map) do
    dynamic_from = Map.get(map, :dynamic_from)
    dynamic_to = Map.get(map, :dynamic_to)

    case {dynamic_from, dynamic_to} do
      {nil, nil} ->
        map

      {nil, _} ->
        {:error, "Cannot use 'dynamic_to' without 'dynamic_from'."}

      {_, nil} ->
        {:error, "Cannot use 'dynamic_from' without 'dynamic_to'."}

      _ ->
        now = Timex.now()
        shift_to_by = if dynamic_to == "now", do: 0, else: str_to_sec(dynamic_to)

        from = Timex.shift(now, seconds: -str_to_sec(dynamic_from))
        to = Timex.shift(now, seconds: -shift_to_by)

        map
        |> Map.put(:from, from |> round_datetime(rounding: :up))
        |> Map.put(:to, to |> round_datetime(rounding: :up))
    end
  end

  def update_dynamic_datetimes(filter), do: filter
end

defmodule Sanbase.Model.Project.ListSelector.Transform do
  import Sanbase.DateTimeUtils

  def args_to_filters_combinator(args) do
    (get_in(args, [:selector, :filters_combinator]) || "and")
    |> to_string()
    |> String.downcase()
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

  def atomize_values(nil), do: nil

  def atomize_values(map) when is_map(map) do
    {to_atomize, rest} = Map.split(map, [:operator, :aggregation, :direction])

    to_atomize
    |> Enum.into(%{}, fn {k, v} ->
      v = if is_binary(v), do: String.to_existing_atom(v), else: v
      {k, v}
    end)
    |> Map.merge(rest)
  end

  def atomize_values(data), do: data

  def transform_from_to(%{from: from, to: to} = map) do
    %{
      map
      | from: if(is_binary(from), do: from_iso8601!(from), else: from),
        to: if(is_binary(to), do: from_iso8601!(to), else: to)
    }
  end

  def transform_from_to(map), do: map

  def update_dynamic_datetimes(nil), do: nil

  def update_dynamic_datetimes(%{} = filter) do
    dynamic_from = Map.get(filter, :dynamic_from)
    dynamic_to = Map.get(filter, :dynamic_to)

    case {dynamic_from, dynamic_to} do
      {nil, nil} ->
        filter

      {nil, _} ->
        {:error, "Cannot use 'dynamic_to' without 'dynamic_from'."}

      {_, nil} ->
        {:error, "Cannot use 'dynamic_from' without 'dynamic_to'."}

      _ ->
        now = Timex.now()

        from = Timex.shift(now, seconds: -str_to_sec(dynamic_from))

        to =
          case dynamic_to do
            "now" ->
              now

            _ ->
              Timex.shift(now, seconds: -str_to_sec(dynamic_to))
          end

        filter
        |> Map.put(:from, from)
        |> Map.put(:to, to)
    end
  end

  def update_dynamic_datetimes(filter), do: filter
end

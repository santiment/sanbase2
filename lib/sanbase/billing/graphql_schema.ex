defmodule Sanbase.Billing.GraphqlSchema do
  @moduledoc ~s"""
  Contains functions that help examining the GraphQL schema.
  It allows you to work easily with access logic of queries.
  """

  require SanbaseWeb.Graphql.Schema

  # NOTE: In case of compile time error for reasons like wrong import_types and
  # similar, the error will be not include the right place where it errored. In this
  # case replace the @query type with the commented one - it has high chances for the
  # proper error location to be revealed
  # @query_type %{fields: %{}}
  @query_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :query)
  @fields @query_type.fields |> Map.keys()

  def min_plan_map() do
    # Metadata looks like this:
    # meta(access: :restricted, min_plan: [sanapi: "PRO", sanbase: "FREE"])
    query_min_plan_map = get_query_min_plan_map()
    metric_min_plan_map = get_metric_min_plan_map()
    signal_min_plan_map = get_signal_min_plan_map()

    query_min_plan_map
    |> Map.merge(metric_min_plan_map)
    |> Map.merge(signal_min_plan_map)
  end

  @doc ~s"""
  Return all query names that have all `fields` with the values specified in
  the corresponding position of the `values` list
  """
  @spec get_field_value_matches(list(atom()), list(any)) :: list(atom())
  def get_field_value_matches(fields, values)
      when is_list(fields) and is_list(values) and length(fields) == length(values) do
    field_value_pairs = Enum.zip(fields, values)

    Enum.filter(@fields, fn f ->
      Enum.all?(field_value_pairs, fn {field, value} ->
        Map.get(@query_type.fields, f) |> Absinthe.Type.meta(field) == value
      end)
    end)
  end

  def get_query_meta_field_list(field) do
    Enum.map(@fields, fn f ->
      {f, Map.get(@query_type.fields, f) |> Absinthe.Type.meta(field)}
    end)
  end

  def get_all_with_access_level(level) do
    # List of {:query, atom()}
    queries_with_access_level =
      get_queries_with_access_level(level)
      |> Enum.map(&{:query, &1})

    # List of {:signal, String.t()}
    signals_with_access_level =
      Sanbase.Signal.access_map()
      |> get_with_access_level(level)
      |> Enum.map(&{:signal, &1})

    # List of {:metric, String.t()}
    metrics_with_access_level =
      Sanbase.Metric.access_map()
      |> get_with_access_level(level)
      |> Enum.map(&{:metric, &1})

    queries_with_access_level ++
      signals_with_access_level ++
      metrics_with_access_level
  end

  def get_with_access_level(access_map, level) do
    access_map
    |> Stream.map(fn {argument, level} ->
      {argument, access_map_to_atom(level)}
    end)
    |> Enum.reduce([], fn
      {argument, ^level}, acc -> [argument | acc]
      _, acc -> acc
    end)
  end

  def get_queries_without_access_level() do
    get_queries_with_access_level(nil) -- [:__typename, :__type, :__schema]
  end

  def get_queries_with_access_level(level) do
    get_field_value_matches([:access], [level])
  end

  # Private functions
  defp get_query_min_plan_map() do
    get_query_meta_field_list(:min_plan)
    |> Enum.into(%{}, fn
      {query, kw_list} when is_list(kw_list) ->
        {{:query, query},
         %{
           "SANAPI" => Keyword.get(kw_list, :sanapi, "FREE"),
           "SANBASE" => Keyword.get(kw_list, :sanbase, "FREE")
         }}

      {query, _} ->
        {{:query, query}, %{"SANAPI" => "FREE", "SANBASE" => "FREE"}}
    end)
  end

  defp get_metric_min_plan_map() do
    Sanbase.Metric.min_plan_map()
    |> Enum.into(%{}, fn
      {metric, product_plan_map} when is_map(product_plan_map) ->
        {{:metric, metric}, product_plan_map}

      {metric, _} ->
        {{:metric, metric}, %{"SANAPI" => "FREE", "SANBASE" => "FREE"}}
    end)
  end

  defp get_signal_min_plan_map() do
    Sanbase.Signal.min_plan_map()
    |> Enum.into(%{}, fn
      {signal, product_plan_map} when is_map(product_plan_map) ->
        {{:signal, signal}, product_plan_map}

      {signal, _} ->
        {{:signal, signal}, %{"SANAPI" => "FREE", "SANBASE" => "FREE"}}
    end)
  end

  defp access_map_to_atom(access_map) do
    case access_map do
      %{"historical" => :free, "realtime" => :free} -> :free
      _ -> :restricted
    end
  end
end

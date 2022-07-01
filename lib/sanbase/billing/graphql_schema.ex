defmodule Sanbase.Billing.GraphqlSchema do
  @moduledoc ~s"""
  Contains functions that help examining the GraphQL schema.
  It allows you to work easily with access logic of queries.
  """

  alias Sanbase.Billing.Product

  require SanbaseWeb.Graphql.Schema

  # NOTE: In case of compile time error for reasons like wrong import_types and
  # similar, the error will be not include the right place where it errored. In this
  # case replace the @query type with the commented one - it has high chances for the
  # proper error location to be revealed
  # @query_type %{fields: %{}}
  @query_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :query)
  @fields @query_type.fields |> Map.keys()

  @doc ~s"""
  Return a map of {query, product_id} key-value pairs. The key is a query that
  needs an extension plan to be accessed and the value is the product_id that
  is needed for that access. If a user has a subscription plan with that product_id
  he/she will have access to that query
  """
  @spec extension_metric_product_map :: %{required(atom()) => Product.product_id()}
  def extension_metric_product_map() do
    @fields
    |> Enum.filter(fn field ->
      Map.get(@query_type.fields, field) |> Absinthe.Type.meta(:access) == :extension
    end)
    |> Enum.map(fn field ->
      # The `product` key value is something like `Product.exchange_wallets_product`
      # so the value is its AST instead of the actual value because of how
      # the graphql schema is being built compile time. It is preferable to have
      # more complicated code here instead of having to make the call at compile
      # time, save it into module attribute and use that instead
      product_ast = Map.get(@query_type.fields, field) |> Absinthe.Type.meta(:product)
      {{_, _, [module, func]}, _, _} = product_ast
      product_id = apply(module, func, [])
      {{:query, field}, product_id}
    end)
    |> Map.new()
  end

  def min_plan_map() do
    # Metadata looks like this:
    # meta(access: :restricted, min_plan: [sanapi: :pro, sanbase: :free])
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
    signals_with_access_level =
      Sanbase.Signal.access_map()
      |> get_with_access_level(level)
      |> Enum.map(&{:signal, &1})

    metrics_with_access_level =
      Sanbase.Metric.access_map()
      |> get_with_access_level(level)
      |> Enum.map(&{:metric, &1})

    Enum.map(get_queries_with_access_level(level), &{:query, &1}) ++
      signals_with_access_level ++ metrics_with_access_level
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
           "SANAPI" => Keyword.get(kw_list, :sanapi, :free),
           "SANBASE" => Keyword.get(kw_list, :sanbase, :free)
         }}

      {query, _} ->
        {{:query, query}, %{"SANAPI" => :free, "SANBASE" => :free}}
    end)
  end

  defp get_metric_min_plan_map() do
    Sanbase.Metric.min_plan_map()
    |> Enum.into(%{}, fn
      {metric, product_plan_map} when is_map(product_plan_map) ->
        {{:metric, metric}, product_plan_map}

      {metric, _} ->
        {{:metric, metric}, %{"SANAPI" => :free, "SANBASE" => :free}}
    end)
  end

  defp get_signal_min_plan_map() do
    Sanbase.Signal.min_plan_map()
    |> Enum.into(%{}, fn
      {signal, product_plan_map} when is_map(product_plan_map) ->
        {{:signal, signal}, product_plan_map}

      {signal, _} ->
        {{:signal, signal}, %{"SANAPI" => :free, "SANBASE" => :free}}
    end)
  end

  defp access_map_to_atom(access_map) do
    case access_map do
      %{"historical" => :free, "realtime" => :free} -> :free
      _ -> :restricted
    end
  end
end

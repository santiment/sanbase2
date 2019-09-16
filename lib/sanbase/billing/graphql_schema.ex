defmodule Sanbase.Billing.GraphqlSchema do
  @moduledoc ~s"""
  Contains functions that help examining the GraphQL schema.
  It allows you to work easily with access logic of queries.
  """

  alias Sanbase.Billing.Product
  alias Sanbase.Clickhouse.Metric
  require SanbaseWeb.Graphql.Schema

  @mutation_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :mutation)
  @mutations_mapset MapSet.new(@mutation_type.fields |> Map.keys())

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
    |> Enum.filter(fn f ->
      Map.get(@query_type.fields, f) |> Absinthe.Type.meta(:access) == :extension
    end)
    |> Enum.map(fn f ->
      # The `product` key value is something like `Product.exchange_wallets_product`
      # so the value is its AST instead of the actual value because of how
      # the graphql schema is being built compile time. It is preferable to have
      # more complicated code here instead of having to make the call at compile
      # time, save it into module attribute and use that instead
      product_ast = Map.get(@query_type.fields, f) |> Absinthe.Type.meta(:product)
      {{_, _, [module, func]}, _, _} = product_ast
      product_id = apply(module, func, [])
      {f, product_id}
    end)
    |> Map.new()
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

  def get_metrics_with_access_level(level) do
    from_schema = get_field_value_matches([:access], [level])

    clickhouse_v2_metrics =
      Enum.filter(Metric.metric_access_map(), fn {_metric, metric_level} ->
        level == metric_level
      end)
      |> Enum.map(fn {metric, _access} -> {:clickhouse_v2_metric, metric} end)

    from_schema ++ clickhouse_v2_metrics
  end

  def get_metrics_without_access_level() do
    get_metrics_with_access_level(nil) -- [:__typename, :__type, :__schema]
  end

  def mutations_mapset(), do: @mutations_mapset
end

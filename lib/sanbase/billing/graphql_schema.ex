defmodule Sanbase.Billing.GraphqlSchema do
  @moduledoc ~s"""
  Contains a single function `get_metrics_with_subscription_plan/1` that examines
  the Absinthe's compile-time build schema.

  It is a different module because functions from the module where a module
  attribute is defined cannot be used
  """
  alias Sanbase.Clickhouse.Metric
  require SanbaseWeb.Graphql.Schema

  @mutation_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :mutation)
  @mutations_mapset MapSet.new(@mutation_type.fields |> Map.keys())

  @query_type Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :query)
  @fields @query_type.fields |> Map.keys()

  def get_extension_products() do
    @query_type.fields
    |> Enum.filter(fn {k, _v} ->
      Map.get(@query_type.fields, k) |> Absinthe.Type.meta(:access) == :extension
    end)
    |> Enum.map(fn {k, _v} ->
      # The `product` key value is something like `Product.exchange_wallets_product`
      # so the value is its AST instead of the actual value because of how
      # the graphql schema is being built compile time. It is preferable to have
      # more complicated code here instead of having to make the call at compile
      # time, save it into module attribute and use that instead
      product_ast = Map.get(@query_type.fields, k) |> Absinthe.Type.meta(:product)
      {{_, _, [module, func]}, _, _} = product_ast
      product_id = apply(module, func, [])
      {k, product_id}
    end)
  end

  def get_field_value_matches(fields, values) do
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

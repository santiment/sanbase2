defmodule Sanbase.Billing.GraphqlSchema do
  @moduledoc ~s"""
  Contains functions that help examining the GraphQL schema.
  It allows you to work easily with access logic of queries.
  """

  alias Sanbase.Billing.Product
  alias Sanbase.Metric

  require SanbaseWeb.Graphql.Schema

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
    query_min_plan_map =
      get_query_meta_field_list(:min_plan)
      |> Enum.into(%{}, fn
        {query, nil} -> {{:query, query}, :free}
        {query, plan} when is_atom(plan) -> {{:query, query}, plan}
      end)

    Metric.min_plan_map()
    |> Enum.into(query_min_plan_map, fn
      {metric, nil} -> {{:metric, metric}, :free}
      {metric, plan} when is_atom(plan) -> {{:metric, metric}, plan}
    end)
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
    Enum.map(get_queries_with_access_level(level), &{:query, &1}) ++
      Enum.map(get_metrics_with_access_level(level), &{:metric, &1})
  end

  def get_metrics_with_access_level(level) do
    Enum.filter(Metric.access_map(), fn {_metric, metric_level} ->
      level == metric_level
    end)
    |> Enum.map(fn {metric, _access} -> metric end)
  end

  def get_queries_with_access_level(level) do
    get_field_value_matches([:access], [level])
  end

  def get_all_without_access_level() do
    get_metrics_with_access_level(nil) -- [:__typename, :__type, :__schema]
  end
end

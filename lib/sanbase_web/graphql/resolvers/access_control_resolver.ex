defmodule SanbaseWeb.Graphql.Resolvers.AccessControlResolver do
  alias Sanbase.Billing.Product
  alias SanbaseWeb.Graphql.Cache

  def get_access_restrictions(_root, args, %{context: context}) do
    plan_name = Map.get(args, :plan) || context[:auth][:plan] || "FREE"
    plan_name = plan_name |> to_string() |> String.upcase()

    product_id =
      Product.id_by_code(Map.get(args, :product)) || context[:product] ||
        context[:subscription_product_id] || Product.product_api()

    product_code = Product.code_by_id(product_id)

    filter = Map.get(args, :filter)

    Cache.wrap(
      fn ->
        restrictions = Sanbase.Billing.Plan.Restrictions.get_all(plan_name, product_code, filter)
        {:ok, restrictions}
      end,
      {:get_access_restrictions, plan_name, product_code, filter}
    ).()
  end

  def get_access_control(_root, _args, _resolution) do
    {:error, "The query does not have a product key in the context."}
  end
end

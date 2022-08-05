defmodule SanbaseWeb.Graphql.Resolvers.AccessControlResolver do
  alias Sanbase.Billing.Product
  alias SanbaseWeb.Graphql.Cache

  def get_access_restrictions(_root, args, %{context: context}) do
    plan = Map.get(args, :plan) || context[:auth][:plan] || "FREE"
    plan = plan |> to_string() |> String.upcase()

    product_id =
      Product.id_by_code(Map.get(args, :product)) || context[:product_id] || Product.product_api()

    Cache.wrap(
      fn ->
        restrictions = Sanbase.Billing.Plan.Restrictions.get_all(plan, product_id)
        {:ok, restrictions}
      end,
      {:get_access_restrictions, plan, product_id}
    ).()
  end

  def get_access_control(_root, _args, _resolution) do
    {:error, "The query does not have a product key in the context."}
  end
end

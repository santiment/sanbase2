defmodule SanbaseWeb.Graphql.Middlewares.SanbaseProductOrigin do
  @behaviour Absinthe.Middleware

  @product_id_sanbase Sanbase.Billing.Product.product_sanbase()

  alias Absinthe.Resolution

  def call(%Resolution{context: %{requested_product_id: @product_id_sanbase}} = resolution, _) do
    resolution
  end

  def call(resolution, _) do
    resolution
    |> Resolution.put_result({:error, "This query/mutation can be executed only from Sanbase"})
  end
end

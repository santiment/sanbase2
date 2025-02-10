defmodule SanbaseWeb.Graphql.Middlewares.SanbaseProductOrigin do
  @moduledoc false
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  @product_id_sanbase Sanbase.Billing.Product.product_sanbase()

  def call(%Resolution{context: %{requested_product_id: @product_id_sanbase}} = resolution, _) do
    resolution
  end

  def call(resolution, _) do
    Resolution.put_result(resolution, {:error, "This query/mutation can be executed only from Sanbase"})
  end
end

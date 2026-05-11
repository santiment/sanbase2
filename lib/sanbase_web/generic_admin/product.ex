defmodule SanbaseWeb.GenericAdmin.Product do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Billing.Product
  def resource_name, do: "products"
  def singular_resource_name, do: "product"

  def resource do
    %{
      actions: []
    }
  end

  def product_link(row) do
    SanbaseWeb.GenericAdmin.resource_link("products", row.product_id, row.product.name)
  end
end

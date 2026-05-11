defmodule SanbaseWeb.GenericAdmin.Currency do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Model.Currency
  def resource_name, do: "currencies"
  def singular_resource_name, do: "currency"

  def resource() do
    %{
      actions: [:show]
    }
  end
end

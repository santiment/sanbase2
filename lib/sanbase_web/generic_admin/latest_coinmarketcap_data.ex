defmodule SanbaseWeb.GenericAdmin.LatestCoinmarketcapData do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Model.LatestCoinmarketcapData
  def resource_name, do: "latest_coinmarketcap_data"
  def singular_resource_name, do: "latest_coinmarketcap_data"

  def resource() do
    %{
      actions: [:show]
    }
  end
end

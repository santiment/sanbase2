defmodule SanbaseWeb.GenericAdmin.MarketSegments do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Model.MarketSegment
  def resource_name, do: "market_segments"
  def singular_resource_name, do: "market_segment"

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:projects],
      new_fields: [:name, :type],
      edit_fields: [:name, :type]
    }
  end
end

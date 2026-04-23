defmodule SanbaseWeb.GenericAdmin.Infrastructure do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Model.Infrastructure
  def resource_name, do: "infrastructures"
  def singular_resource_name, do: "infrastructure"

  def resource() do
    %{
      actions: [:new, :edit],
      new_fields: [:code],
      edit_fields: [:code]
    }
  end
end

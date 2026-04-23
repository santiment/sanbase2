defmodule SanbaseWeb.GenericAdmin.Tag do
  @behaviour SanbaseWeb.GenericAdmin
  alias Sanbase.Tag
  def schema_module, do: Tag
  def resource_name, do: "tags"
  def singular_resource_name, do: "tag"

  def resource do
    %{
      actions: [:new, :edit, :delete],
      preloads: [],
      index_fields: [:id, :name],
      new_fields: [:name],
      edit_fields: [:name]
    }
  end
end

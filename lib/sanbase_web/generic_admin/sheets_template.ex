defmodule SanbaseWeb.GenericAdmin.SheetsTemplate do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.SheetsTemplate
  def resource_name, do: "sheets_templates"
  def singular_resource_name, do: "sheets_template"

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [
        :id,
        :name,
        :description,
        :url,
        :is_pro,
        :inserted_at,
        :updated_at
      ],
      new_fields: [
        :name,
        :description,
        :url,
        :is_pro
      ],
      edit_fields: [
        :name,
        :description,
        :url,
        :is_pro
      ],
      preloads: [],
      belongs_to_fields: %{}
    }
  end
end

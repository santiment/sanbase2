defmodule SanbaseWeb.GenericAdmin.ProjectEcosystemMapping do
  def schema_module, do: Sanbase.ProjectEcosystemMapping

  def resource() do
    %{
      actions: [:new, :edit],
      index_fields: [:id, :project_id, :ecosystem_id, :inserted_at, :updated_at],
      new_fields: [:project, :ecosystem],
      edit_fields: [:project, :ecosystem],
      preloads: [:project, :ecosystem],
      belongs_to_fields: %{
        project: %{resource: "projects", search_fields: [:name, :slug, :ticker]},
        ecosystem: %{resource: "ecosystems", search_fields: [:ecosystem]}
      }
    }
  end
end

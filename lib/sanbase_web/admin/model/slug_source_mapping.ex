defmodule Sanbase.ExAdmin.Model.Project.SlugSourceMapping do
  use ExAdmin.Register

  register_resource Sanbase.Model.Project.SlugSourceMapping do
    form slug_source_mapping do
      inputs do
        input(slug_source_mapping, :source_slug)
        input(slug_source_mapping, :source)

        input(
          slug_source_mapping,
          :project,
          collection: from(p in Sanbase.Model.Project, order_by: p.name) |> Sanbase.Repo.all()
        )
      end
    end

    controller do
      after_filter(:set_defaults, only: [:new])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    {conn, params, resource |> set_project_default(params)}
  end

  defp set_project_default(%{project_id: nil} = slug_source_mapping, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> slug_source_mapping
      project_id -> Map.put(slug_source_mapping, :project_id, project_id)
    end
  end
end

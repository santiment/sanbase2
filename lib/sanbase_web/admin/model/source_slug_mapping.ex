defmodule SanbaseWeb.ExAdmin.Model.Project.SourceSlugMapping do
  use ExAdmin.Register

  register_resource Sanbase.Model.Project.SourceSlugMapping do
    form source_slug_mapping do
      inputs do
        input(
          source_slug_mapping,
          :project,
          collection: from(p in Sanbase.Model.Project, order_by: p.name) |> Sanbase.Repo.all()
        )

        input(source_slug_mapping, :source,
          collection: ["cryptocompare", "coinmarketcap", "binance"]
        )

        input(source_slug_mapping, :slug)
      end
    end

    controller do
      after_filter(:set_defaults, only: [:new])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    {conn, params, resource |> set_project_default(params)}
  end

  defp set_project_default(%{project_id: nil} = source_slug_mapping, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> source_slug_mapping
      project_id -> Map.put(source_slug_mapping, :project_id, project_id)
    end
  end
end

defmodule Sanbase.ExAdmin.Model.ProjectMarketSegment do
  use ExAdmin.Register

  alias Sanbase.Model.{Project, MarketSegment}

  register_resource Sanbase.Model.Project.ProjectMarketSegment do
    show _ do
      attributes_table(all: true)
    end

    form project_market_segment do
      inputs do
        input(
          project_market_segment,
          :project,
          collection: from(p in Project, order_by: p.name) |> Sanbase.Repo.all()
        )

        input(
          project_market_segment,
          :market_segment,
          collection: from(ms in MarketSegment, order_by: ms.name) |> Sanbase.Repo.all()
        )
      end
    end

    controller do
      after_filter(:set_defaults, only: [:new])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    resource =
      resource
      |> set_project_default(params)

    {conn, params, resource}
  end

  defp set_project_default(resource, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> resource
      project_id -> Map.put(resource, :project_id, project_id)
    end
  end
end

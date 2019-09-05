defmodule Sanbase.ExAdmin.Model.MarketSegment do
  use ExAdmin.Register

  import Ecto.Query

  register_resource Sanbase.Model.MarketSegment do
    show ms do
      attributes_table(all: true)

      panel "Projects with this Market Segment" do
        table_for projects_with_market_segment(ms) do
          column(:name, link: true)
          column(:ticker)
          column(:slug)
        end
      end
    end
  end

  def projects_with_market_segment(ms) do
    project_ids =
      from(
        ms in Sanbase.Model.Project.ProjectMarketSegment,
        where: ms.market_segment_id == ^ms.id,
        select: ms.project_id
      )
      |> Sanbase.Repo.all()

    from(p in Sanbase.Model.Project, where: p.id in ^project_ids)
    |> Sanbase.Repo.all()
  end
end

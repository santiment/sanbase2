defmodule Sanbase.Repo.Migrations.FillProjectMarketSegmentsTable do
  use Ecto.Migration

  alias Sanbase.Project

  def up do
    setup()
    projects = projects_with_market_segment()

    insert_data =
      Enum.map(projects, fn project ->
        %{project_id: project.id, market_segment_id: project.market_segment.id}
      end)

    Sanbase.Repo.insert_all(Project.ProjectMarketSegment, insert_data, on_conflict: :nothing)
  end

  def down, do: :ok

  defp projects_with_market_segment() do
    Project.List.projects()
    |> Sanbase.Repo.preload([:market_segment])
    |> Enum.reject(fn %{market_segment: ms} -> ms == nil end)
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
  end
end

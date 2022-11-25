defmodule Sanbase.Project.ProjectMarketSegment do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Project
  alias Sanbase.Model.MarketSegment

  schema "project_market_segments" do
    belongs_to(:project, Project)
    belongs_to(:market_segment, MarketSegment)
  end

  def changeset(%__MODULE__{} = ms, attrs \\ %{}) do
    ms
    |> cast(attrs, [:project_id, :market_segment_id])
    |> validate_required([:project_id, :market_segment_id])
  end
end

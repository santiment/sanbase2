defmodule Sanbase.Model.Project.ProjectMarketSegment do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Model.Project
  alias Sanbase.Model.MarketSegment

  @primary_key false
  schema "project_market_segments" do
    belongs_to(:project, Project, primary_key: true)
    belongs_to(:market_segment, MarketSegment, primary_key: true)

    timestamps()
  end

  def changeset(%__MODULE__{} = ms, attrs \\ %{}) do
    ms
    |> cast(attrs, [:project_id, :market_segment_id])
    |> validate_required([:project_id, :market_segment_id])
  end
end

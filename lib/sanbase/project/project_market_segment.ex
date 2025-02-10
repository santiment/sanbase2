defmodule Sanbase.Project.ProjectMarketSegment do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Model.MarketSegment
  alias Sanbase.Project

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

defmodule Sanbase.Model.MarketSegment do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.MarketSegment
  alias Sanbase.Model.Project

  schema "market_segments" do
    field(:name, :string)

    many_to_many(
      :projects,
      Project,
      join_through: "project_market_segments",
      on_replace: :delete,
      on_delete: :delete_all
    )
  end

  @doc false
  def changeset(%MarketSegment{} = market_segment, attrs \\ %{}) do
    market_segment
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end

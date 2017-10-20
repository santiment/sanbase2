defmodule Sanbase.Model.TeamMember do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.TeamMember
  alias Sanbase.Model.Team
  alias Sanbase.Model.Country


  schema "team_members" do
    belongs_to :team, Team
    belongs_to :country, Country
  end

  @doc false
  def changeset(%TeamMember{} = team_member, attrs \\ %{}) do
    team_member
    |> cast(attrs, [])
    |> validate_required([])
  end
end

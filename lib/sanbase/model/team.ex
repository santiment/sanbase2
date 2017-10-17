defmodule Sanbase.Model.Team do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Team
  alias Sanbase.Model.Project
  alias Sanbase.Model.TeamMember


  schema "teams" do
    field :advisor_linkedin_available, :integer
    field :advisors, :integer
    field :av_no_linkedin_network_advisors, :integer
    field :avno_linkedin_network_team, :decimal
    field :business_people, :integer
    field :dev_people, :integer
    field :linkedin_profiles_project, :integer
    field :pics_available, :boolean
    field :real_names, :boolean
    field :team_website, :integer
    belongs_to :project, Project
    has_many :members, TeamMember
  end

  @doc false
  def changeset(%Team{} = team, attrs \\ %{}) do
    team
    |> cast(attrs, [:website, :avno_linkedin_network_team, :dev_people, :business_people, :real_names, :pics_available, :linkedin_profiles_project, :advisors, :advisor_linkedin_available, :av_no_linkedin_network_advisors])
    |> validate_required([:website, :avno_linkedin_network_team, :dev_people, :business_people, :real_names, :pics_available, :linkedin_profiles_project, :advisors, :advisor_linkedin_available, :av_no_linkedin_network_advisors])
    |> unique_constraint(:project_id)
  end
end

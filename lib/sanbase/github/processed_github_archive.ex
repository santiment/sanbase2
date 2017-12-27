defmodule Sanbase.Github.ProcessedGithubArchive do
  use Ecto.Schema
  alias Sanbase.Repo

  alias Sanbase.Model.Project

  schema "processed_github_archives" do
    belongs_to(:project, Project)
    field(:archive, :string)

    timestamps()
  end

  def mark_as_processed(project_id, archive) do
    %__MODULE__{project_id: project_id, archive: archive}
    |> Repo.insert!(on_conflict: :nothing)
  end
end

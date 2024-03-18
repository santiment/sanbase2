defmodule Sanbase.Ecosystem.ChangeSuggestion do
  @moduledoc ~s"""

  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Project

  @statuses ["pending_approval", "approved", "declined"]

  schema "project_ecosystem_labels_change_suggestions" do
    field(:added_ecosystems, {:array, :string})
    field(:removed_ecosystems, {:array, :string})
    field(:notes, :string)
    field(:status, :string, default: "pending_approval")

    belongs_to(:project, Project)

    timestamps()
  end

  @doc false
  def changeset(%__MODULE__{} = suggestion, attrs) do
    suggestion
    |> cast(attrs, [:project_id, :added_ecosystems, :removed_ecosystems, :notes, :status])
    |> validate_required([:project_id])
    |> validate_inclusion(:status, @statuses)
  end

  def list_all_submissions() do
    from(s in __MODULE__, preload: [:project]) |> Sanbase.Repo.all()
  end

  @doc ~s"""
  Create
  """
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Update the status by a moderator
  """
  def update_status(id, new_status) when new_status in @statuses do
    record = Sanbase.Repo.get!(__MODULE__, id)

    record
    |> changeset(%{status: new_status})
    |> Sanbase.Repo.update()
    |> then(fn result ->
      if new_status == "approved" and record.status == "pending_approval",
        do: maybe_apply_changes(result)
    end)
  end

  defp maybe_apply_changes({:ok, suggestion}) do
    # Add
    for ecosystem <- suggestion.added_ecosystems do
      {:ok, _} = Sanbase.ProjectEcosystemMapping.create(suggestion.project_id, ecosystem)
    end

    # Remove
    for ecosystem <- suggestion.removed_ecosystems do
      {:ok, _} = Sanbase.ProjectEcosystemMapping.remove(suggestion.project_id, ecosystem)
    end

    {:ok, suggestion}
  end

  defp maybe_apply_changes({:error, changeset}) do
    {:error, changeset}
  end
end

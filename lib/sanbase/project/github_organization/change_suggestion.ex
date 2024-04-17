defmodule Sanbase.Project.GithubOrganization.ChangeSuggestion do
  @moduledoc ~s"""
  Store and apply (or reject, or undo) change suggestions to the github organizations of a project
  submitted by users.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Project

  @statuses ["pending_approval", "approved", "declined"]

  schema "project_github_organizations_change_suggestions" do
    field(:added_organizations, {:array, :string})
    field(:removed_organizations, {:array, :string})
    field(:notes, :string)
    field(:status, :string, default: "pending_approval")

    belongs_to(:project, Project)

    timestamps()
  end

  @doc false
  def changeset(%__MODULE__{} = suggestion, attrs) do
    suggestion
    |> cast(attrs, [:project_id, :added_organizations, :removed_organizations, :notes, :status])
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
  Undo an approved or declined suggestion.
  Approved suggestion is undone by undoing the proposed changes and changing the status back to pending_approval
  Declined suggestion is undone by just setting the status back to pending_approval
  """
  def undo_suggestion(id) when is_integer(id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_record, fn _, _ ->
      case get_record(id) do
        {:ok, %{status: status}} when status == "pending_approval" ->
          {:error, "Record with id #{id} is not approved or declined, so it cannot be undone"}

        {:ok, record} ->
          {:ok, record}

        {:error, error} ->
          {:error, error}
      end
    end)
    |> Ecto.Multi.run(:undo_changes, fn _, %{get_record: record} ->
      case record.status do
        # Undoing an approved suggestion reverts the applied changes
        "approved" ->
          suggestion = %{
            record
            | added_organizations: record.removed_organizations,
              removed_organizations: record.added_organizations
          }

          apply_suggestions(suggestion)

        # Undoing a declined suggestion does not apply any changes, only
        # updates the status
        "declined" ->
          {:ok, :noop}
      end
    end)
    |> Ecto.Multi.run(:make_status_pending, fn _, %{get_record: record} ->
      do_update_status(record, "pending_approval")
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{make_status_pending: record}} -> {:ok, record}
      {:error, _name, error, _changes_so_far} -> {:error, error}
    end
  end

  @doc ~s"""
  Update the status by a moderator
  """
  def update_status(id, new_status) when is_integer(id) and new_status in @statuses do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_record, fn _, _ -> get_record(id) end)
    |> Ecto.Multi.run(:maybe_apply_suggestions, fn _, %{get_record: record} ->
      if new_status == "approved" and record.status == "pending_approval",
        do: apply_suggestions(record),
        else: {:ok, :noop}
    end)
    |> Ecto.Multi.run(:update_status, fn _, %{get_record: record} ->
      do_update_status(record, new_status)
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{update_status: record}} -> {:ok, record}
      {:error, _name, error, _changes_so_far} -> {:error, error}
    end
  end

  defp get_record(id) do
    case Sanbase.Repo.get(__MODULE__, id) do
      nil -> {:error, "Record with id #{id} not found"}
      record -> {:ok, record}
    end
  end

  defp do_update_status(%__MODULE__{} = record, new_status) do
    record
    |> changeset(%{status: new_status})
    |> Sanbase.Repo.update()
  end

  defp apply_suggestions(suggestion) do
    added =
      for org <- suggestion.added_organizations do
        Sanbase.Project.GithubOrganization.add_github_organization(suggestion.project_id, org)
      end

    removed =
      for org <- suggestion.removed_organizations do
        Sanbase.Project.GithubOrganization.remove_github_organization(suggestion.project_id, org)
      end

    case Enum.any?(added ++ removed, &match?({:error, _}, &1)) do
      false -> {:ok, suggestion}
      true -> {:error, "Failed to apply changes"}
    end
  end
end

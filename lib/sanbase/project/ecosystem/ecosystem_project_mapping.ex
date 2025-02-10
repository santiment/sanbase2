defmodule Sanbase.ProjectEcosystemMapping do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Ecosystem
  alias Sanbase.Project

  @type project_id :: non_neg_integer()
  @type ecosystem_id :: non_neg_integer()
  @type ecosystem_name :: String.t()

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          project_id: project_id(),
          ecosystem_id: ecosystem_id(),
          project: Project.t(),
          ecosystem: Ecosystem.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
  @timestamps_opts [type: :utc_datetime]

  schema "project_ecosystem_mappings" do
    belongs_to(:project, Project)
    belongs_to(:ecosystem, Ecosystem)
    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs) do
    mapping
    |> cast(attrs, [:project_id, :ecosystem_id])
    |> validate_required([:project_id, :ecosystem_id])
    |> unique_constraint([:project_id, :ecosystem_id])
  end

  @spec create(project_id, ecosystem_id | ecosystem_name) :: {:ok}
  def create(project_id, ecosystem_id) when is_integer(ecosystem_id) do
    %__MODULE__{}
    |> changeset(%{project_id: project_id, ecosystem_id: ecosystem_id})
    |> Sanbase.Repo.insert(on_conflict: :nothing)
  end

  def create(project_id, ecosystem) when is_binary(ecosystem) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_ecosystem_id, fn _, _ ->
      Sanbase.Ecosystem.get_id_by_name(ecosystem)
    end)
    |> Ecto.Multi.run(:create_mapping, fn _, %{get_ecosystem_id: ecosystem_id} ->
      create(project_id, ecosystem_id)
    end)
    |> Sanbase.Repo.transaction()
    |> process_transaction_result(:create_mapping)
  end

  def remove(project_id, ecosystem_id) when is_integer(ecosystem_id) do
    query =
      from(m in __MODULE__,
        where: m.project_id == ^project_id and m.ecosystem_id == ^ecosystem_id
      )

    {count, nil} = Sanbase.Repo.delete_all(query)
    {:ok, "Removed #{count} records"}
  end

  def remove(project_id, ecosystem) when is_binary(ecosystem) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_ecosystem_id, fn _, _ ->
      Sanbase.Ecosystem.get_id_by_name(ecosystem)
    end)
    |> Ecto.Multi.run(:remove_mapping, fn _, %{get_ecosystem_id: ecosystem_id} ->
      remove(project_id, ecosystem_id)
    end)
    |> Sanbase.Repo.transaction()
    |> process_transaction_result(:remove_mapping)
  end

  # Private functions

  defp process_transaction_result({:ok, map}, ok_field), do: {:ok, map[ok_field]}

  defp process_transaction_result({:error, _, error, _}, _ok_field), do: {:error, error}
end

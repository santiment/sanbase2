defmodule Sanbase.Project.ContractAddress do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Project

  require Logger

  schema "contract_addresses" do
    field(:address, :string)
    field(:decimals, :integer)
    field(:label, :string)
    field(:description, :string)

    field(:decimals_scrape_attempted_at, :utc_datetime)

    belongs_to(:project, Project)

    timestamps()
  end

  def changeset(%__MODULE__{} = contract, attrs \\ %{}) do
    contract
    |> cast(attrs, [
      :address,
      :decimals,
      :label,
      :description,
      :project_id,
      :decimals_scrape_attempted_at
    ])
    |> validate_required([:address, :project_id])
    |> unique_constraint([:project_id, :address],
      message: "The combination of project and contract address must be unique."
    )
  end

  @doc ~s"""
  Add contract to a project.

  If the contract already exists, only the fields present in `attrs` are
  updated. Fields that are not given are kept as they are. A `nil` decimals
  value means unknown decimals and does not remove the existing decimals.

  The `main` label is never removed or moved by this function:
    - a contract that is already labeled `main` keeps its label;
    - a `main` label is not applied if another contract of the project is
      already labeled `main`. In this case the existing label of the contract
      is kept and a warning is logged.

  The `main` label can be changed only by editing the contract directly
  (e.g. from the admin panel).

  Returns the contract as stored in the database.
  """
  @spec add_contract(%Project{}, %{
          required(:address) => address,
          optional(:decimals) => decimals,
          optional(:description) => String.t(),
          optional(:label) => String.t()
        }) :: {:ok, %__MODULE__{}} | {:error, any()}
        when address: String.t(), decimals: non_neg_integer()
  def add_contract(
        %Project{id: project_id},
        %{} = attrs
      ) do
    if Map.get(attrs, :label) == "main" do
      Sanbase.Repo.transaction(fn ->
        # Lock the project row to serialize the `main` check and the insert.
        # Otherwise two concurrent calls for different addresses could both
        # see no `main` contract and both insert one.
        from(p in Project, where: p.id == ^project_id, lock: "FOR UPDATE", select: p.id)
        |> Sanbase.Repo.one()

        attrs
        |> maybe_drop_main_label(project_id)
        |> do_add_contract(project_id)
        |> case do
          {:ok, contract} -> contract
          {:error, error} -> Sanbase.Repo.rollback(error)
        end
      end)
    else
      do_add_contract(attrs, project_id)
    end
  end

  # Do not create a second `main` contract
  defp maybe_drop_main_label(attrs, project_id) do
    address = Map.get(attrs, :address)

    if main_on_other_address?(project_id, address) do
      Logger.warning(
        "[ContractAddress] Not labeling #{address} as main for project #{project_id}. " <>
          "The project already has a main contract. Change it from the admin panel."
      )

      Map.delete(attrs, :label)
    else
      attrs
    end
  end

  defp do_add_contract(attrs, project_id) do
    map = %{
      address: Map.get(attrs, :address),
      decimals: Map.get(attrs, :decimals),
      label: Map.get(attrs, :label),
      description: Map.get(attrs, :description),
      project_id: project_id
    }

    %__MODULE__{}
    |> changeset(map)
    |> Sanbase.Repo.insert(
      on_conflict: on_conflict_query(attrs),
      conflict_target: [:address, :project_id],
      # Return the stored row, not the input, as some fields may be kept
      returning: true
    )
  end

  # Update only the fields given by the caller. An existing `main` label is
  # never changed.
  defp on_conflict_query(attrs) do
    set =
      attrs
      |> Map.take([:decimals, :description])
      |> Map.reject(fn {key, value} -> key == :decimals and is_nil(value) end)
      |> Map.to_list()
      |> Keyword.put(:updated_at, NaiveDateTime.utc_now(:second))

    query = from(ca in __MODULE__, update: [set: ^set])

    case Map.fetch(attrs, :label) do
      {:ok, label} ->
        from(ca in query,
          update: [
            set: [
              label:
                fragment("CASE WHEN ? = 'main' THEN ? ELSE ? END", ca.label, ca.label, ^label)
            ]
          ]
        )

      :error ->
        query
    end
  end

  defp main_on_other_address?(project_id, address) do
    from(ca in __MODULE__,
      where: ca.project_id == ^project_id and ca.label == "main" and ca.address != ^address
    )
    |> Sanbase.Repo.exists?()
  end

  def list_to_main_contract_address(list) when is_list(list) do
    list = Enum.reject(list, &is_nil(&1.decimals))

    if Enum.empty?(list) do
      nil
    else
      Enum.find(list, &(&1.label == "main")) || List.first(list)
    end
  end

  def list_to_latest_onchain_contract_address(list) when is_list(list) do
    list = list |> Enum.reject(&is_nil(&1.decimals))

    Enum.find(list, &(&1.label == "latest_onchain_contract")) ||
      Enum.find(list, &(&1.label == "main")) ||
      List.first(list)
  end

  def delete_by_project_id_and_address(project_id, address) do
    from(ca in __MODULE__,
      where: ca.project_id == ^project_id and ca.address == ^address
    )
    |> Sanbase.Repo.delete_all()
  end

  def all_with_infrastructure() do
    from(ca in __MODULE__,
      join: p in assoc(ca, :project),
      join: i in assoc(p, :infrastructure),
      preload: [:project, project: [:infrastructure]]
    )
    |> Sanbase.Repo.all()
  end
end

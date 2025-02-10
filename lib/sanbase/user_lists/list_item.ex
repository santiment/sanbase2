defmodule Sanbase.UserList.ListItem do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.BlockchainAddress.BlockchainAddressUserPair
  alias Sanbase.Project
  alias Sanbase.Repo
  alias Sanbase.UserList

  schema "list_items" do
    belongs_to(:project, Project)
    belongs_to(:blockchain_address_user_pair, BlockchainAddressUserPair)
    belongs_to(:user_list, UserList)
  end

  def changeset(list_item, attrs \\ %{}) do
    list_item
    |> cast(attrs, [:project_id, :blockchain_address_user_pair_id, :user_list_id])
    |> validate_required([:user_list_id])
    |> check_constraint(:exactly_one_type_of_item, name: :only_one_fk)
  end

  def get_projects(%UserList{id: id}) do
    from(
      li in __MODULE__,
      where: li.user_list_id == ^id and not is_nil(li.project_id),
      preload: [:project]
    )
    |> Sanbase.Repo.all()
    |> Enum.map(& &1.project)
  end

  def get_blockchain_addresses(%UserList{id: id}) do
    from(
      li in __MODULE__,
      where: li.user_list_id == ^id and not is_nil(li.blockchain_address_user_pair_id),
      preload: [
        :blockchain_address_user_pair,
        blockchain_address_user_pair: [
          :labels,
          :blockchain_address,
          blockchain_address: :infrastructure
        ]
      ]
    )
    |> Sanbase.Repo.all()
    |> Enum.map(& &1.blockchain_address_user_pair)
  end

  def create(list_items) do
    list_items
    |> Enum.map(&changeset(%__MODULE__{}, &1))
    |> Enum.with_index()
    |> Enum.reduce(
      Ecto.Multi.new(),
      fn {changeset, offset}, multi ->
        Ecto.Multi.insert(multi, offset, changeset, on_conflict: :nothing)
      end
    )
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, Map.values(result)}
      {:error, _name, error, _changes_so_far} -> {:error, error}
    end
  end

  def delete([%{project_id: _} | _] = list_items) do
    list_items
    |> Enum.reduce(__MODULE__, fn map, query ->
      or_where(query, [li], li.user_list_id == ^map.user_list_id and li.project_id == ^map.project_id)
    end)
    |> Repo.delete_all()
  end

  def delete([%{blockchain_address_id: _} | _] = list_items) do
    list_items
    |> Enum.reduce(__MODULE__, fn map, query ->
      or_where(
        query,
        [li],
        li.user_list_id == ^map.user_list_id and li.blockchain_address_id == ^map.blockchain_address_id
      )
    end)
    |> Repo.delete_all()
  end

  def delete([]), do: {0, nil}
end

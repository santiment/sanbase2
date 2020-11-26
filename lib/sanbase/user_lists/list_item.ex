defmodule Sanbase.UserList.ListItem do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.UserList
  alias Sanbase.Model.Project
  alias Sanbase.BlockchainAddress.BlockchainAddressUserPair

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
end

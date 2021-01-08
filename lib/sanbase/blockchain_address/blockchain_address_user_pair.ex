defmodule Sanbase.BlockchainAddress.BlockchainAddressUserPair do
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.BlockchainAddress.BlockchainAddressLabel, as: Label

  @labels_join_through_table "blockchain_address_user_pairs_labels"

  schema "blockchain_address_user_pairs" do
    field(:notes, :string)

    belongs_to(:user, Sanbase.Accounts.User)
    belongs_to(:blockchain_address, Sanbase.BlockchainAddress)

    many_to_many(
      :labels,
      Label,
      join_through: @labels_join_through_table,
      join_keys: [blockchain_address_user_pair_id: :id, label_id: :id],
      on_replace: :delete,
      on_delete: :delete_all
    )
  end

  def changeset(%__MODULE__{} = addr, attrs \\ %{}) do
    addr
    |> cast(attrs, [:user_id, :blockchain_address_id, :notes])
    |> validate_required([:user_id, :blockchain_address_id])
    |> put_labels(attrs)
  end

  def maybe_create(attrs_list) when is_list(attrs_list) do
    attrs_list
    |> Enum.map(&changeset(%__MODULE__{}, &1))
    |> Enum.with_index()
    |> Enum.reduce(
      Ecto.Multi.new(),
      fn {changeset, offset}, multi ->
        multi
        |> Ecto.Multi.insert(offset, changeset,
          on_conflict: {:replace, [:user_id]},
          conflict_target: [:user_id, :blockchain_address_id],
          returning: true
        )
      end
    )
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, Map.values(result)}
      {:error, _name, error, _changes_so_far} -> {:error, error}
    end
  end

  # Private functions

  defp put_labels(%{valid?: true} = changeset, %{labels: label_names} = attrs)
       when not is_nil(label_names) do
    %{user_id: user_id, blockchain_address_id: blockchain_address_id} = attrs

    {:ok, labels} = Label.find_or_insert_by_names(label_names)

    drop_pair_labels(user_id, blockchain_address_id)

    changeset
    |> put_assoc(:labels, labels)
  end

  defp put_labels(changeset, _attrs), do: changeset

  defp drop_pair_labels(user_id, blockchain_address_id) do
    id =
      from(pair in __MODULE__,
        where: pair.user_id == ^user_id and pair.blockchain_address_id == ^blockchain_address_id,
        select: pair.id
      )
      |> Sanbase.Repo.one()

    if id != nil do
      from(pair_label in @labels_join_through_table,
        where: pair_label.blockchain_address_user_pair_id == ^id
      )
      |> Sanbase.Repo.delete_all()
    end
  end
end

defmodule Sanbase.BlockchainAddress.BlockchainAddressUserPair do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.BlockchainAddress.BlockchainAddressLabel, as: Label

  @labels_join_through_table "blockchain_address_user_pairs_labels"

  @preloads [:user, :blockchain_address, :labels]
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

  def changeset(%__MODULE__{} = pair, attrs \\ %{}) do
    pair
    |> cast(attrs, [:user_id, :blockchain_address_id, :notes])
    |> validate_required([:user_id, :blockchain_address_id])
    |> put_labels(attrs)
  end

  def by_selector(%{id: id}, user_id) do
    from(pair in __MODULE__, where: pair.id == ^id, preload: ^@preloads)
    |> Sanbase.Repo.one()
    |> case do
      %__MODULE__{user_id: ^user_id} = pair ->
        {:ok, pair}

      %__MODULE__{user_id: _} ->
        {:error, "Blockchain address pair with id #{id} does not belong to the querying user."}

      _ ->
        {:error, "Blockchain address pair with #{id} does not exist"}
    end
  end

  def by_selector(%{address: address, infrastructure: infrastructure} = selector, user_id) do
    from(
      pair in __MODULE__,
      join: blockchain_address in assoc(pair, :blockchain_address),
      on: pair.blockchain_address_id == blockchain_address.id,
      join: infrastructure in assoc(blockchain_address, :infrastructure),
      on: blockchain_address.infrastructure_id == infrastructure.id,
      where:
        blockchain_address.address == ^address and infrastructure.code == ^infrastructure and
          pair.user_id == ^user_id,
      preload: ^@preloads
    )
    |> Sanbase.Repo.one()
    |> case do
      %__MODULE__{user_id: _} = pair ->
        {:ok, pair}

      _ ->
        {:error, "Blockchain address user pair with selector #{inspect(selector)} does not exist"}
    end
  end

  def by_selector(%{blockchain_address_id: blockchain_address_id}, user_id) do
    from(pair in __MODULE__,
      where: pair.user_id == ^user_id and pair.blockchain_address_id == ^blockchain_address_id,
      preload: ^@preloads
    )
    |> Sanbase.Repo.one()
    |> case do
      %__MODULE__{user_id: ^user_id} = pair ->
        {:ok, pair}

      _ ->
        {:error,
         """
         Blockchain address user pair for user id #{user_id} and\
         blockchain address id #{blockchain_address_id} does not exist
         """}
    end
  end

  def update(%__MODULE__{} = pair, attrs) do
    # These fields are needed by put_labels/2
    attrs =
      attrs
      |> Map.put(:user_id, pair.user_id)
      |> Map.put(:blockchain_address_id, pair.blockchain_address_id)

    pair
    |> cast(attrs, [:notes])
    |> put_labels(attrs)
    |> Sanbase.Repo.update()
  end

  def maybe_create(attrs_list) when is_list(attrs_list) do
    attrs_list
    |> Enum.map(&changeset(%__MODULE__{}, &1))
    |> Enum.with_index()
    |> Enum.reduce(
      Ecto.Multi.new(),
      fn {changeset, offset}, multi ->
        # notes is an optional field. It should be replaced only if it is in the changeset
        notes_change = if Map.has_key?(changeset.changes, :notes), do: [:notes], else: []

        Ecto.Multi.insert(multi, offset, changeset,
          on_conflict: {:replace, notes_change ++ [:user_id, :blockchain_address_id]},
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

  def create(address, infrastructure, user_id) do
    {:ok, blockchain_address} =
      Sanbase.BlockchainAddress.by_selector(%{address: address, infrastructure: infrastructure})

    %__MODULE__{}
    |> changeset(%{blockchain_address_id: blockchain_address.id, user_id: user_id})
    |> Sanbase.Repo.insert()
    |> case do
      {:ok, struct} -> {:ok, Sanbase.Repo.preload(struct, @preloads)}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp put_labels(%{valid?: true} = changeset, %{labels: label_names} = attrs) when not is_nil(label_names) do
    %{user_id: user_id, blockchain_address_id: blockchain_address_id} = attrs

    {:ok, labels} = Label.find_or_insert_by_names(label_names)

    drop_pair_labels(user_id, blockchain_address_id)

    put_assoc(changeset, :labels, labels)
  end

  defp put_labels(changeset, _attrs), do: changeset

  defp drop_pair_labels(user_id, blockchain_address_id) do
    id =
      Sanbase.Repo.one(
        from(pair in __MODULE__,
          where: pair.user_id == ^user_id and pair.blockchain_address_id == ^blockchain_address_id,
          select: pair.id
        )
      )

    if id != nil do
      Sanbase.Repo.delete_all(
        from(pair_label in @labels_join_through_table, where: pair_label.blockchain_address_user_pair_id == ^id)
      )
    end
  end
end

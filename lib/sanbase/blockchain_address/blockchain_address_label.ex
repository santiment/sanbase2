defmodule Sanbase.BlockchainAddress.BlockchainAddressLabel do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "blockchain_address_labels" do
    field(:name, :string)
    field(:notes, :string)
  end

  def changeset(%__MODULE__{} = addr, attrs \\ %{}) do
    addr
    |> cast(attrs, [:name, :notes])
    |> validate_required([:name])
  end

  def find_or_insert_by_names(names) do
    names
    |> Enum.map(&changeset(%__MODULE__{}, %{name: &1}))
    |> Enum.with_index()
    |> Enum.reduce(
      Ecto.Multi.new(),
      fn {changeset, offset}, multi ->
        Ecto.Multi.insert(multi, offset, changeset,
          on_conflict: {:replace, [:name]},
          conflict_target: [:name],
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
end

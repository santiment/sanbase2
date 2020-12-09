defmodule Sanbase.BlockchainAddress do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Model.Infrastructure

  # @primary_key {:id, :integer, read_after_writes: true}
  schema "blockchain_addresses" do
    field(:address, :string)
    field(:notes, :string)

    belongs_to(:infrastructure, Infrastructure)
  end

  def changeset(%__MODULE__{} = addr, attrs \\ %{}) do
    addr
    |> cast(attrs, [:address, :infrastructure_id, :notes])
    |> validate_required([:address])
  end

  def by_id(id) do
    case Sanbase.Repo.get(__MODULE__, id) do
      nil -> {:error, "Blockchain address with #{id} does not exist."}
      %__MODULE__{} = addr -> {:ok, addr}
    end
  end

  def to_internal_format(address) do
    case Regex.match?(~r/^0x([A-Fa-f0-9]{40})$/, address) do
      true -> String.downcase(address)
      _ -> address
    end
  end

  def maybe_create(%{address: _, infrastructure_id: _} = map) do
    %__MODULE__{}
    |> changeset(map)
    |> Sanbase.Repo.insert(on_conflict: :nothing)
  end

  def maybe_create(list) when is_list(list) do
    changesets = list |> Enum.map(&changeset(%__MODULE__{}, &1)) |> Enum.with_index()

    Enum.reduce(
      changesets,
      Ecto.Multi.new(),
      fn {changeset, offset}, multi ->
        multi
        |> Ecto.Multi.insert(offset, changeset,
          on_conflict: {:replace, [:address]},
          conflict_target: [:address, :infrastructure_id],
          returning: true
        )
      end
    )
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, Map.values(result)}
      {:error, error} -> {:error, error}
    end
  end
end

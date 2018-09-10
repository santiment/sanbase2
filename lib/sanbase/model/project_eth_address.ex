defmodule Sanbase.Model.ProjectEthAddress do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Model.Project

  require Logger

  @eth_decimals 1_000_000_000_000_000_000

  schema "project_eth_address" do
    field(:address, :string)
    belongs_to(:project, Project)
    field(:source, :string)
    field(:comments, :string)
  end

  @doc false
  def changeset(%ProjectEthAddress{} = project_eth_address, attrs \\ %{}) do
    project_eth_address
    |> cast(attrs, [:address, :project_id, :source, :comments])
    |> validate_required([:address, :project_id])
    |> update_change(:address, &String.downcase/1)
    |> unique_constraint(:address)
  end

  def balance(%ProjectEthAddress{address: address}) do
    case Sanbase.InternalServices.Parity.get_eth_balance(address) do
      {:ok, balance} ->
        balance / @eth_decimals

      {:error, error} ->
        Logger.error(
          "Cannot fetch the ETH balance for #{address} from Parity. Reason: #{inspect(error)}"
        )

        nil
    end
  end
end

defmodule Sanbase.ProjectEthAddress do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Project

  require Logger

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
    |> update_change(:address, &Sanbase.BlockchainAddress.to_internal_format/1)
    |> unique_constraint(:address)
  end

  def balance(%ProjectEthAddress{address: address}) do
    case Sanbase.Balance.current_balance(address, "ethereum") do
      {:ok, [%{balance: balance}]} -> {:ok, balance}
      {:error, error} -> {:error, error}
    end
  end
end

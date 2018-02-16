defmodule Sanbase.Repo.Migrations.LowercaseProjectAddresses do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Model.{ProjectEthAddress, ProjectBtcAddress}
  alias Sanbase.Repo
  alias Ecto.Multi

  def change do
    migrate_eth()
    migrate_btc()
  end

  def migrate_eth() do
    updates =
      Repo.all(ProjectEthAddress)
      |> Enum.map(fn %ProjectEthAddress{address: address} = eth_addr ->
        eth_addr
        |> ProjectEthAddress.changeset(%{address: String.downcase(address)})
      end)
      |> Enum.map(&Repo.update/1)
  end

  def migrate_btc() do
    updates =
      Repo.all(ProjectBtcAddress)
      |> Enum.map(fn %ProjectBtcAddress{address: address} = eth_addr ->
        eth_addr
        |> ProjectBtcAddress.changeset(%{address: String.downcase(address)})
      end)
      |> Enum.map(&Repo.update/1)
  end
end

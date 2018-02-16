defmodule Sanbase.Repo.Migrations.LowercaseProjectAddresses do
  use Ecto.Migration

  alias Sanbase.Model.{ProjectEthAddress, ProjectBtcAddress}
  alias Sanbase.Repo

  def change do
    migrate_eth()
    migrate_btc()
  end

  def migrate_eth() do
    Repo.all(ProjectEthAddress)
    |> Enum.map(fn %ProjectEthAddress{address: address} = eth_addr ->
      eth_addr
      |> ProjectEthAddress.changeset(%{address: String.downcase(address)})
    end)
    |> Enum.map(&Repo.update/1)
  end

  def migrate_btc() do
    Repo.all(ProjectBtcAddress)
    |> Enum.map(fn %ProjectBtcAddress{address: address} = eth_addr ->
      eth_addr
      |> ProjectBtcAddress.changeset(%{address: String.downcase(address)})
    end)
    |> Enum.map(&Repo.update/1)
  end
end

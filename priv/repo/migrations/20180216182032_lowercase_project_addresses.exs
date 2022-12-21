defmodule Sanbase.Repo.Migrations.LowercaseProjectAddresses do
  use Ecto.Migration

  alias Sanbase.ProjectEthAddress
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
end

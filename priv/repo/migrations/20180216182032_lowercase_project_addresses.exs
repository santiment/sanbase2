defmodule Sanbase.Repo.Migrations.LowercaseProjectAddresses do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.ProjectEthAddress
  alias Sanbase.Repo

  def change do
    migrate_eth()
    migrate_btc()
  end

  def migrate_eth do
    ProjectEthAddress
    |> Repo.all()
    |> Enum.map(fn %ProjectEthAddress{address: address} = eth_addr ->
      ProjectEthAddress.changeset(eth_addr, %{address: String.downcase(address)})
    end)
    |> Enum.map(&Repo.update/1)
  end
end

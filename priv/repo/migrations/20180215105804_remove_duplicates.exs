defmodule Sanbase.Repo.Migrations.RemoveDuplicates do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo

  alias Sanbase.Model.{
    LatestEthWalletData,
    LatestBtcWalletData
  }

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;")

    migrate_eth()

    migrate_btc()
  end

  def down do
    # We delete duplicated data - that cannot be rollbacked
  end

  defp migrate_eth() do
    alter table(:project_eth_address) do
      modify(:address, :citext, null: false)
    end

    latest_eth_data = Repo.all(LatestEthWalletData)

    filtered_eth_data =
      latest_eth_data
      |> Enum.reject(fn %LatestEthWalletData{address: address} ->
        count_address(latest_eth_data, address) > 1 && address != String.downcase(address)
      end)
      |> Enum.map(&Map.from_struct/1)
      |> Enum.map(&Map.drop(&1, [:__meta__]))

    Repo.delete_all(LatestEthWalletData)

    alter table(:latest_eth_wallet_data) do
      modify(:address, :citext, null: false)
    end

    Repo.insert_all(LatestEthWalletData, filtered_eth_data)
  end

  defp migrate_btc() do
    alter table(:project_btc_address) do
      modify(:address, :citext, null: false)
    end

    latest_btc_data = Repo.all(LatestBtcWalletData)

    filtered_btc_data =
      latest_btc_data
      |> Enum.reject(fn %LatestBtcWalletData{address: address} ->
        count_address(latest_btc_data, address) > 1 && address != String.downcase(address)
      end)
      |> Enum.map(&Map.from_struct/1)
      |> Enum.map(&Map.drop(&1, [:__meta__]))

    Repo.delete_all(LatestBtcWalletData)

    alter table(:latest_btc_wallet_data) do
      modify(:address, :citext, null: false)
    end

    filtered_btc_data
    Repo.insert_all(LatestBtcWalletData, filtered_btc_data)
  end

  defp count_address(map, addr) do
    Enum.count(map, fn %LatestEthWalletData{address: address} ->
      String.downcase(addr) == String.downcase(address)
    end)
  end

  defp count_address(map, addr) do
    Enum.count(map, fn %LatestBtcWalletData{address: address} ->
      String.downcase(addr) == String.downcase(address)
    end)
  end
end

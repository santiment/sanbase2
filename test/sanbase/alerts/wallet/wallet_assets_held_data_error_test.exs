defmodule Sanbase.Alert.WalletAssetsHeldDataErrorTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Alert.Trigger.WalletAssetsHeldTriggerSettings
  alias Sanbase.Clickhouse.HistoricalBalance

  @error_msg "[0a97368a-8c26-46b6-a8b8-08d621dbc515] Cannot execute database query."
  @address "0x77fd8239ecf7abceaf9f2c14f5acae950e7b3e98"

  setup do
    Sanbase.Cache.clear_all()
    :ok
  end

  @tag capture_log: true
  test "get_data/1 returns an error when the assets held query fails" do
    Sanbase.Mock.prepare_mock2(
      &HistoricalBalance.assets_held_by_address/1,
      {:error, @error_msg}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:error, _} = WalletAssetsHeldTriggerSettings.get_data(settings([@address]))
    end)
  end

  test "get_data/1 returns the held slugs in the order of the addresses" do
    addresses = [@address, "0x1111111111111111111111111111111111111111"]

    Sanbase.Mock.prepare_mock2(
      &HistoricalBalance.assets_held_by_address/1,
      {:ok, [%{slug: "ethereum", balance: 1.0}, %{slug: "santiment", balance: 2.0}]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, data} = WalletAssetsHeldTriggerSettings.get_data(settings(addresses))
      assert data == Enum.map(addresses, &{&1, ["ethereum", "santiment"]})
    end)
  end

  defp settings(addresses) do
    %WalletAssetsHeldTriggerSettings{
      type: "wallet_assets_held",
      channel: "telegram",
      selector: %{infrastructure: "ETH"},
      target: %{address: addresses},
      filtered_target: %{list: addresses}
    }
  end
end

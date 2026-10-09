defmodule Sanbase.Alert.WalletAssetsHeldDataErrorTest do
  # Reproduces SANBASE-BACKEND-PROD-G7R:
  #   MatchError: no match of right hand side value: {:error, "[...] Cannot execute
  #   database query. ..."} in anonymous fn/1 in
  #   Sanbase.Alert.Trigger.WalletAssetsHeldTriggerSettings.assets_held/1
  #
  # `assets_held/1` hard-matches `{:ok, _} = HistoricalBalance.assets_held_by_address/1`
  # inside the cache function. A ClickHouse error raises inside the evaluator's
  # `Sanbase.Parallel.map/3` worker; the worker is linked to the scheduler process, so
  # one failing address aborts the evaluation of every wallet_assets_held alert in the
  # run. (`get_data/1` even has an `Enum.reject(&match?({:error, _}, &1))` that shows the
  # intent was to tolerate per-address errors, but it is never reached.)
  #
  # Desired behaviour: `get_data/1` does not raise; it returns `{:error, reason}` (which
  # `TriggerSettingsBase.default_evaluate/3` logs and treats as "not triggered") or skips
  # the failing address.
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
  test "get_data/1 does not raise when the assets held query fails" do
    settings = settings([@address])

    Sanbase.Mock.prepare_mock2(
      &HistoricalBalance.assets_held_by_address/1,
      {:error, @error_msg}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try do
          {:ok, WalletAssetsHeldTriggerSettings.get_data(settings)}
        rescue
          e -> {:raised, e}
        end

      assert {:ok, get_data_result} = result

      assert match?({:error, _}, get_data_result) or
               match?({:ok, list} when is_list(list), get_data_result)

      # The failing address must not be reported as holding no assets - that would
      # make the next successful evaluation report all its assets as newcomers.
      refute match?({:ok, [{@address, []}]}, get_data_result)
    end)
  end

  test "get_data/1 still returns the held slugs on success" do
    settings = settings([@address])

    Sanbase.Mock.prepare_mock2(
      &HistoricalBalance.assets_held_by_address/1,
      {:ok, [%{slug: "ethereum", balance: 1.0}, %{slug: "santiment", balance: 2.0}]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, [{@address, ["ethereum", "santiment"]}]} =
               WalletAssetsHeldTriggerSettings.get_data(settings)
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

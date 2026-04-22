defmodule Sanbase.Metric.UtilsContractTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory

  alias Sanbase.Metric.Utils

  defmodule FakeAdapter do
    def available_metrics(selector, opts) do
      send(self(), {:fake_adapter_called, selector, opts})
      {:ok, ["fake_metric"]}
    end
  end

  test "available_metrics_for_contract/3 forwards opts to the adapter module" do
    project = insert(:random_erc20_project)
    %{address: address} = hd(project.contract_addresses)

    Utils.available_metrics_for_contract(FakeAdapter, address, lookback_days: 365)

    assert_received {:fake_adapter_called, %{slug: slug}, opts}
    assert slug == project.slug
    assert Keyword.get(opts, :lookback_days) == 365
  end

  test "available_metrics_for_contract/3 defaults to empty opts when not provided" do
    project = insert(:random_erc20_project)
    %{address: address} = hd(project.contract_addresses)

    Utils.available_metrics_for_contract(FakeAdapter, address)

    assert_received {:fake_adapter_called, _selector, []}
  end

  test "available_metrics_for_contract/3 returns [] when no project matches contract" do
    assert Utils.available_metrics_for_contract(FakeAdapter, "0xdoesnotexist", lookback_days: 365) ==
             []

    refute_received {:fake_adapter_called, _, _}
  end
end

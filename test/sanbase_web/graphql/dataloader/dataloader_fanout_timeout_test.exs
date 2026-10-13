defmodule SanbaseWeb.Graphql.DataloaderFanoutTimeoutTest do
  # A slow or failing fan-out fails its whole field, never part of it, without exiting the batch
  use Sanbase.DataCase, async: false

  import Mock

  alias SanbaseWeb.Graphql.ClickhouseDataloader
  alias SanbaseWeb.Graphql.LabelsDataloader
  alias SanbaseWeb.Graphql.PriceDataloader

  @tag capture_log: true
  test "a slow aggregated metric does not exit the batch; the other one still resolves" do
    from = ~U[2026-09-01 00:00:00Z]
    to = ~U[2026-09-02 00:00:00Z]
    opts = [only_finalized_data: false, aggregation: :sum]

    fast_selector = {"dev_activity_1d", from, to, opts}
    slow_selector = {"slow_metric", from, to, opts}

    args = [
      %{selector: fast_selector, slug: "bitcoin", metric: "dev_activity_1d", opts: opts},
      %{selector: slow_selector, slug: "ethereum", metric: "slow_metric", opts: opts}
    ]

    with_mocks [
      {Sanbase.Parallel, [:passthrough], dataloader_timeout: fn -> 300 end},
      {Sanbase.Metric, [:passthrough],
       aggregated_timeseries_data: fn
         "slow_metric", _selector, _from, _to, _opts -> Process.sleep(:infinity)
         _metric, %{slug: slugs}, _from, _to, _opts -> {:ok, Map.new(slugs, &{&1, 10.0})}
       end}
    ] do
      result = ClickhouseDataloader.query(:aggregated_metric, args, nil)

      assert Map.get(result, fast_selector) == %{"bitcoin" => 10.0}
      refute Map.has_key?(result, slow_selector)
    end
  end

  describe "PriceDataloader.query(:volume_change_24h, ..)" do
    # 100 slugs fill the first chunk; "slug-101" lands alone in the second one
    setup do
      %{args: Enum.map(1..101, &%{slug: "slug-#{&1}"})}
    end

    test "returns the change for every slug", ctx do
      with_mock Sanbase.Metric,
                [:passthrough],
                volume_mock(fn slugs -> {:ok, volumes(slugs)} end) do
        result = PriceDataloader.query(:volume_change_24h, ctx.args, nil)

        assert map_size(result) == 101
        assert Map.get(result, "slug-101") == 0.0
      end
    end

    @tag capture_log: true
    test "a failing chunk fails the field for every slug", ctx do
      volume_fn = fn slugs ->
        if "slug-101" in slugs, do: {:error, "boom"}, else: {:ok, volumes(slugs)}
      end

      with_mock Sanbase.Metric, [:passthrough], volume_mock(volume_fn) do
        result = PriceDataloader.query(:volume_change_24h, ctx.args, nil)

        assert map_size(result) == 101
        assert Enum.all?(Map.values(result), &match?({:error, _}, &1))
      end
    end

    defp volume_mock(volume_fn) do
      [
        aggregated_timeseries_data: fn "volume_usd", %{slug: slugs}, _from, _to ->
          volume_fn.(slugs)
        end
      ]
    end

    defp volumes(slugs), do: Map.new(slugs, &{&1, 100.0})
  end

  @tag capture_log: true
  test "a failing address labels chunk fails the field for every address" do
    # 50 addresses fill the first chunk; the "bad" address lands alone in the second one
    addresses = Enum.map(1..50, &"0xaddress#{&1}") ++ ["0xbad"]

    with_mock Sanbase.Clickhouse.Label, [:passthrough],
      get_address_labels: fn nil, addresses ->
        if "0xbad" in addresses,
          do: {:error, "boom"},
          else: {:ok, Map.new(addresses, &{&1, [%{name: "label"}]})}
      end do
      result = LabelsDataloader.query(:address_labels, addresses, nil)

      assert map_size(result) == 51
      assert Enum.all?(Map.values(result), &match?({:error, _}, &1))
    end
  end
end

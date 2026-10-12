defmodule SanbaseWeb.Graphql.DataloaderFanoutTimeoutTest do
  # A slow or failing fan-out fails its whole field, never part of it, without exiting the batch
  use Sanbase.DataCase, async: false

  import Mock

  alias SanbaseWeb.Graphql.BalanceDataloader
  alias SanbaseWeb.Graphql.ClickhouseDataloader
  alias SanbaseWeb.Graphql.LabelsDataloader
  alias SanbaseWeb.Graphql.PriceDataloader

  defp parallel_mock(), do: {Sanbase.Parallel, [:passthrough], dataloader_timeout: fn -> 300 end}

  describe "ClickhouseDataloader.query(:aggregated_metric, ..)" do
    setup do
      from = ~U[2026-09-01 00:00:00Z]
      to = ~U[2026-09-02 00:00:00Z]
      opts = [only_finalized_data: false, aggregation: :sum]

      fast_selector = {"dev_activity_1d", from, to, opts}
      slow_selector = {"slow_metric", from, to, opts}

      args = [
        %{selector: fast_selector, slug: "bitcoin", metric: "dev_activity_1d", opts: opts},
        %{selector: slow_selector, slug: "ethereum", metric: "slow_metric", opts: opts}
      ]

      metric_mock =
        {Sanbase.Metric, [:passthrough],
         aggregated_timeseries_data: fn
           "slow_metric", _selector, _from, _to, _opts ->
             Process.sleep(:infinity)

           _metric, %{slug: slugs}, _from, _to, _opts ->
             {:ok, Map.new(slugs, &{&1, 10.0})}
         end}

      %{
        args: args,
        fast_selector: fast_selector,
        slow_selector: slow_selector,
        metric_mock: metric_mock
      }
    end

    test "a slow selector does not exit the batch; the fast selector still resolves", ctx do
      with_mocks [parallel_mock(), ctx.metric_mock] do
        result = ClickhouseDataloader.query(:aggregated_metric, ctx.args, nil)

        assert Map.get(result, ctx.fast_selector) == %{"bitcoin" => 10.0}
        refute Map.has_key?(result, ctx.slow_selector)
      end
    end
  end

  describe "PriceDataloader.query(:volume_change_24h, ..)" do
    # 100 fast slugs fill the first chunk; the "bad" slug lands alone in the second one
    setup do
      fast_slugs = Enum.map(1..100, &"fast-slug-#{&1}")
      %{fast_slugs: fast_slugs, args: Enum.map(fast_slugs ++ ["bad-slug"], &%{slug: &1})}
    end

    test "all chunks succeed", ctx do
      with_mocks [parallel_mock(), volume_mock(fn -> :ok end)] do
        result = PriceDataloader.query(:volume_change_24h, ctx.args, nil)

        assert map_size(result) == 101
        assert Map.get(result, "bad-slug") == 0.0
      end
    end

    for {name, bad_chunk} <- [
          slow: quote(do: fn -> Process.sleep(:infinity) end),
          failing: quote(do: fn -> {:error, "boom"} end)
        ] do
      test "a #{name} chunk fails the whole field", ctx do
        with_mocks [parallel_mock(), volume_mock(unquote(bad_chunk))] do
          assert PriceDataloader.query(:volume_change_24h, ctx.args, nil) == %{}
        end
      end
    end

    defp volume_mock(bad_chunk_fun) do
      {Sanbase.Metric, [:passthrough],
       aggregated_timeseries_data: fn "volume_usd", %{slug: slugs}, _from, _to ->
         case "bad-slug" in slugs && bad_chunk_fun.() do
           {:error, _} = error -> error
           _ -> {:ok, Map.new(slugs, &{&1, 100.0})}
         end
       end}
    end
  end

  describe "LabelsDataloader.query(:address_labels, ..)" do
    # 50 fast addresses fill the first chunk; the "bad" address lands alone in the second one
    setup do
      %{addresses: Enum.map(1..50, &"0xfast#{&1}") ++ ["0xbad"]}
    end

    test "all chunks succeed", ctx do
      with_mocks [parallel_mock(), labels_mock(fn -> :ok end)] do
        result = LabelsDataloader.query(:address_labels, ctx.addresses, nil)

        assert map_size(result) == 51
        assert Map.get(result, "0xbad") == [%{name: "label"}]
      end
    end

    for {name, bad_chunk} <- [
          slow: quote(do: fn -> Process.sleep(:infinity) end),
          failing: quote(do: fn -> {:error, "boom"} end)
        ] do
      test "a #{name} chunk fails the whole field", ctx do
        with_mocks [parallel_mock(), labels_mock(unquote(bad_chunk))] do
          assert LabelsDataloader.query(:address_labels, ctx.addresses, nil) == %{}
        end
      end
    end

    defp labels_mock(bad_chunk_fun) do
      {Sanbase.Clickhouse.Label, [:passthrough],
       get_address_labels: fn nil, addresses ->
         case "0xbad" in addresses && bad_chunk_fun.() do
           {:error, _} = error -> error
           _ -> {:ok, Map.new(addresses, &{&1, [%{name: "label"}]})}
         end
       end}
    end
  end

  describe "BalanceDataloader.query(:address_selector_current_balance, ..)" do
    setup do
      fast_selector = %{slug: "ethereum"}
      slow_selector = %{slug: "slow-chain"}

      args = [
        {"0x1111111111111111111111111111111111111111", fast_selector},
        {"0x2222222222222222222222222222222222222222", slow_selector}
      ]

      balance_mock =
        {Sanbase.Clickhouse.HistoricalBalance, [:passthrough],
         current_balance: fn
           %{slug: "slow-chain"}, _addresses ->
             Process.sleep(:infinity)

           _selector, addresses ->
             {:ok, Enum.map(addresses, &%{address: &1, balance: 5.0})}
         end}

      %{
        args: args,
        fast_selector: fast_selector,
        slow_selector: slow_selector,
        balance_mock: balance_mock
      }
    end

    test "a slow selector does not exit the batch; the fast selector still resolves", ctx do
      with_mocks [parallel_mock(), ctx.balance_mock] do
        result = BalanceDataloader.query(:address_selector_current_balance, ctx.args, nil)

        assert Map.get(
                 result,
                 {"0x1111111111111111111111111111111111111111", ctx.fast_selector}
               ) == 5.0

        assert Map.get(result, {:total_balance, ctx.fast_selector}) == 5.0

        refute Map.has_key?(
                 result,
                 {"0x2222222222222222222222222222222222222222", ctx.slow_selector}
               )
      end
    end
  end
end

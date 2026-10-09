defmodule SanbaseWeb.Graphql.DataloaderFanoutTimeoutTest do
  # Reproduces the "Task #PID<..> started from #PID<..> terminating ... exited in:
  # Task.Supervised.stream(N) ** (EXIT) time out" Sentry issues:
  #
  #   * SANBASE-BACKEND-PROD-R   - ClickhouseDataloader.query(:aggregated_metric, ..)  (60_000)
  #   * SANBASE-BACKEND-PROD-F9H - PriceDataloader.query(:volume_change_24h, ..)       (25_000)
  #   * SANBASE-BACKEND-PROD-GA0 - BalanceDataloader.query(:address_selector_current_balance, ..) (55_000)
  #
  # Each of these Dataloader.KV batch functions fans out with `Sanbase.Parallel.map/3`
  # (or `flat_map/3`) using the default `on_timeout: :exit`. When a single group's
  # ClickHouse query is slow, the stream exits the Dataloader batch task, which crashes
  # (one Sentry event) and nils out *every* field in the batch, including the groups
  # that finished fine.
  #
  # Desired behaviour:
  #   1. A slow group does not take the whole batch down - the fast groups still resolve.
  #   2. The fan-out budget outlasts the ClickHouse query budget (docs/timeouts.md), so a
  #      slow-but-legitimate query gets to return its own result/error instead of being
  #      killed by an inner timeout that is shorter than the query it wraps.
  #
  # To keep the test fast, `Sanbase.Parallel` is wrapped (passthrough) so that the
  # configured timeout is captured and then shrunk to a few hundred ms.
  use Sanbase.DataCase, async: false

  import Mock

  alias SanbaseWeb.Graphql.BalanceDataloader
  alias SanbaseWeb.Graphql.ClickhouseDataloader
  alias SanbaseWeb.Graphql.PriceDataloader

  @shrunk_timeout_ms 300

  defp parallel_mocks(test_pid) do
    shrink = fn opts ->
      send(test_pid, {:parallel_timeout, Keyword.get(opts, :timeout)})
      Keyword.put(opts, :timeout, @shrunk_timeout_ms)
    end

    [
      map: fn collection, func, opts ->
        passthrough([collection, func, shrink.(opts)])
      end,
      flat_map: fn collection, func, opts ->
        passthrough([collection, func, shrink.(opts)])
      end
    ]
  end

  defp clickhouse_budget_ms() do
    Application.get_env(:sanbase, Sanbase.ClickhouseRepo) |> Keyword.fetch!(:timeout)
  end

  defp captured_timeout() do
    assert_received {:parallel_timeout, timeout}
    # `nil` means Sanbase.Parallel's 25s default is used
    timeout || 25_000
  end

  describe "ClickhouseDataloader.query(:aggregated_metric, ..) (SANBASE-BACKEND-PROD-R)" do
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
      with_mocks [
        {Sanbase.Parallel, [:passthrough], parallel_mocks(self())},
        ctx.metric_mock
      ] do
        result = ClickhouseDataloader.query(:aggregated_metric, ctx.args, nil)

        assert Map.get(result, ctx.fast_selector) == %{"bitcoin" => 10.0}

        slow_result = Map.get(result, ctx.slow_selector)
        assert slow_result == nil or match?({:error, _}, slow_result)
      end
    end

    test "the fan-out timeout outlasts the ClickHouse query budget", ctx do
      with_mocks [
        {Sanbase.Parallel, [:passthrough], parallel_mocks(self())},
        {Sanbase.Metric, [:passthrough],
         aggregated_timeseries_data: fn _metric, %{slug: slugs}, _from, _to, _opts ->
           {:ok, Map.new(slugs, &{&1, 10.0})}
         end}
      ] do
        _ = ClickhouseDataloader.query(:aggregated_metric, ctx.args, nil)

        assert captured_timeout() > clickhouse_budget_ms()
      end
    end
  end

  describe "PriceDataloader.query(:volume_change_24h, ..) (SANBASE-BACKEND-PROD-F9H)" do
    setup do
      # 100 fast slugs fill the first chunk (chunk size is 100); the slow slug lands
      # alone in the second chunk.
      fast_slugs = Enum.map(1..100, &"fast-slug-#{&1}")
      args = Enum.map(fast_slugs ++ ["slow-slug"], &%{slug: &1})

      %{fast_slugs: fast_slugs, args: args}
    end

    test "a slow chunk does not exit the batch; the fast chunk still resolves", ctx do
      with_mocks [
        {Sanbase.Parallel, [:passthrough], parallel_mocks(self())},
        {Sanbase.Metric, [:passthrough],
         aggregated_timeseries_data: fn "volume_usd", %{slug: slugs}, _from, _to ->
           if "slow-slug" in slugs, do: Process.sleep(:infinity)
           {:ok, Map.new(slugs, &{&1, 100.0})}
         end}
      ] do
        result = PriceDataloader.query(:volume_change_24h, ctx.args, nil)

        for slug <- ctx.fast_slugs do
          assert Map.get(result, slug) == 0.0
        end

        assert Map.get(result, "slow-slug") == nil
      end
    end

    test "the fan-out timeout outlasts the ClickHouse query budget", ctx do
      with_mocks [
        {Sanbase.Parallel, [:passthrough], parallel_mocks(self())},
        {Sanbase.Metric, [:passthrough],
         aggregated_timeseries_data: fn "volume_usd", %{slug: slugs}, _from, _to ->
           {:ok, Map.new(slugs, &{&1, 100.0})}
         end}
      ] do
        _ = PriceDataloader.query(:volume_change_24h, ctx.args, nil)

        # Every chunk runs two sequential ClickHouse queries
        assert captured_timeout() > clickhouse_budget_ms()
      end
    end
  end

  describe "BalanceDataloader.query(:address_selector_current_balance, ..) (SANBASE-BACKEND-PROD-GA0)" do
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
      with_mocks [
        {Sanbase.Parallel, [:passthrough], parallel_mocks(self())},
        ctx.balance_mock
      ] do
        result = BalanceDataloader.query(:address_selector_current_balance, ctx.args, nil)

        assert Map.get(
                 result,
                 {"0x1111111111111111111111111111111111111111", ctx.fast_selector}
               ) == 5.0

        assert Map.get(result, {:total_balance, ctx.fast_selector}) == 5.0

        assert Map.get(
                 result,
                 {"0x2222222222222222222222222222222222222222", ctx.slow_selector}
               ) == nil
      end
    end

    test "the fan-out timeout outlasts the ClickHouse query budget", ctx do
      with_mocks [
        {Sanbase.Parallel, [:passthrough], parallel_mocks(self())},
        {Sanbase.Clickhouse.HistoricalBalance, [:passthrough],
         current_balance: fn _selector, addresses ->
           {:ok, Enum.map(addresses, &%{address: &1, balance: 5.0})}
         end}
      ] do
        _ = BalanceDataloader.query(:address_selector_current_balance, ctx.args, nil)

        assert captured_timeout() > clickhouse_budget_ms()
      end
    end
  end
end

defmodule Sanbase.Clickhouse.MetricAdapter.LabeledBalanceTest do
  # Not async: changes the application env
  use Sanbase.DataCase, async: false

  alias Sanbase.Clickhouse.MetricAdapter
  alias Sanbase.Clickhouse.MetricAdapter.LabeledBalance

  @from ~U[2026-10-10 00:00:00Z]
  @to ~U[2026-10-15 00:00:00Z]
  @binance "santiment/binance:v1"

  setup do
    env = Application.get_env(:sanbase, LabeledBalance)
    on_exit(fn -> Application.put_env(:sanbase, LabeledBalance, env) end)
    :ok
  end

  defp set_from_delta_slugs(value) do
    Application.put_env(:sanbase, LabeledBalance, from_delta_slugs: value)
  end

  # Return the ids for the ids query and `data_rows` for the view query. The SQL of
  # the view query is sent to the test process.
  defp mock_clickhouse(ids_rows, data_rows) do
    test_pid = self()

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, fn sql, _args, _opts ->
      if sql =~ "'metric' AS kind" do
        {:ok, %{rows: ids_rows}}
      else
        send(test_pid, {:view_sql, sql})
        {:ok, %{rows: data_rows}}
      end
    end)
  end

  defp ids_rows(assets, labels) do
    [["metric", "combined_labeled_balance_delta", 1184, ""]] ++
      Enum.map(assets, fn {slug, id} -> ["asset", slug, id, ""] end) ++
      Enum.map(labels, fn {fqn, id, asset_name} -> ["label", fqn, id, asset_name] end)
  end

  describe "source/3" do
    test "is legacy when the env var is empty" do
      set_from_delta_slugs("")

      assert LabeledBalance.source("labelled_historical_balance", %{slug: "bitcoin"}, []) ==
               :legacy
    end

    test "uses the allowlist" do
      set_from_delta_slugs("bitcoin, litecoin")
      metric = "labelled_historical_balance"

      assert LabeledBalance.source(metric, %{slug: "bitcoin"}, []) == :delta
      assert LabeledBalance.source(metric, %{slug: ["bitcoin", "litecoin"]}, []) == :delta
      assert LabeledBalance.source(metric, %{slug: ["bitcoin", "ethereum"]}, []) == :legacy
      assert LabeledBalance.source(metric, %{slug: "ethereum"}, []) == :legacy
    end

    test "is delta for all slugs with *" do
      set_from_delta_slugs("*")

      assert LabeledBalance.source("labelled_historical_balance", %{slug: "ethereum"}, []) ==
               :delta

      assert LabeledBalance.source("combined_historical_balance_funds", %{slug: "bitcoin"}, []) ==
               :delta

      assert LabeledBalance.enabled_for_all_slugs?("labelled_historical_balance")
    end

    test "the source option overrides the env var" do
      set_from_delta_slugs("")
      metric = "labelled_historical_balance"
      assert LabeledBalance.source(metric, %{slug: "bitcoin"}, source: :delta) == :delta

      set_from_delta_slugs("*")
      assert LabeledBalance.source(metric, %{slug: "bitcoin"}, source: :legacy) == :legacy
    end

    test "is legacy for other metrics, other versions and other selectors" do
      set_from_delta_slugs("*")

      assert LabeledBalance.source("labelled_historical_balance_changes", %{slug: "bitcoin"}, []) ==
               :legacy

      assert LabeledBalance.source("price_usd", %{slug: "bitcoin"}, []) == :legacy

      assert LabeledBalance.source("labelled_historical_balance", %{slug: "bitcoin"},
               version: "2.0"
             ) == :legacy

      assert LabeledBalance.source("labelled_historical_balance", %{contract_address: "0x1"}, []) ==
               :legacy

      refute LabeledBalance.enabled_for_all_slugs?("labelled_historical_balance_changes")
    end
  end

  describe "pair_assets_with_labels/4" do
    @metric "labelled_historical_balance"

    test "one label is paired with every asset" do
      assets = %{"ethereum" => 1681, "chainlink" => 1526}

      assert {:ok, pairs} =
               LabeledBalance.pair_assets_with_labels(
                 @metric,
                 ["ethereum", "chainlink"],
                 assets,
                 %{
                   @binance => {1, ""}
                 }
               )

      assert Enum.sort(pairs) == [{1526, 1}, {1681, 1}]
    end

    test "one label per asset" do
      assets = %{"ethereum" => 1681, "chainlink" => 1526}

      labels = %{
        "santiment/whale_usd_balance(ethereum):v1" => {1, "ethereum"},
        "santiment/whale_usd_balance(chainlink):v1" => {2, "chainlink"}
      }

      assert {:ok, pairs} =
               LabeledBalance.pair_assets_with_labels(
                 @metric,
                 ["ethereum", "chainlink"],
                 assets,
                 labels
               )

      assert Enum.sort(pairs) == [{1526, 2}, {1681, 1}]
    end

    test "labels of unknown slugs are dropped" do
      labels = %{
        "santiment/whale_usd_balance(ethereum):v1" => {1, "ethereum"},
        "santiment/whale_usd_balance(unknown):v1" => {2, "unknown"}
      }

      assert {:ok, [{1681, 1}]} =
               LabeledBalance.pair_assets_with_labels(
                 @metric,
                 ["ethereum", "unknown"],
                 %{"ethereum" => 1681},
                 labels
               )
    end

    test "several labels for one asset are rejected" do
      labels = %{@binance => {1, ""}, "santiment/coinbase:v1" => {2, ""}}

      assert {:error, error} =
               LabeledBalance.pair_assets_with_labels(
                 @metric,
                 ["ethereum"],
                 %{"ethereum" => 1681},
                 labels
               )

      assert error =~ "Multiple labels per asset are not supported"

      labels = %{
        "santiment/whale_usd_balance(ethereum):v1" => {1, "ethereum"},
        "santiment/other(ethereum):v1" => {2, "ethereum"}
      }

      assert {:error, _} =
               LabeledBalance.pair_assets_with_labels(
                 @metric,
                 ["ethereum"],
                 %{"ethereum" => 1681},
                 labels
               )
    end

    test "unknown labels return no pairs" do
      assert {:ok, []} =
               LabeledBalance.pair_assets_with_labels(
                 @metric,
                 ["ethereum"],
                 %{"ethereum" => 1681},
                 %{}
               )
    end
  end

  describe "fill_gaps/1" do
    test "fills the intervals without changes with the last balance" do
      rows = [
        %{datetime: ~U[2026-10-10 00:00:00Z], value: 0.0, has_changed: 0},
        %{datetime: ~U[2026-10-11 00:00:00Z], value: 5.0, has_changed: 1},
        %{datetime: ~U[2026-10-12 00:00:00Z], value: 0.0, has_changed: 0},
        %{datetime: ~U[2026-10-13 00:00:00Z], value: 0.0, has_changed: 0},
        %{datetime: ~U[2026-10-14 00:00:00Z], value: 7.0, has_changed: 1}
      ]

      assert LabeledBalance.fill_gaps(rows) == [
               %{datetime: ~U[2026-10-11 00:00:00Z], value: 5.0},
               %{datetime: ~U[2026-10-12 00:00:00Z], value: 5.0},
               %{datetime: ~U[2026-10-13 00:00:00Z], value: 5.0},
               %{datetime: ~U[2026-10-14 00:00:00Z], value: 7.0}
             ]
    end

    test "fills OHLC with the last close" do
      zero = %{open: 0.0, high: 0.0, low: 0.0, close: 0.0}

      rows = [
        %{
          datetime: ~U[2026-10-11 00:00:00Z],
          value_ohlc: %{open: 1.0, high: 9.0, low: 0.5, close: 3.0},
          has_changed: 1
        },
        %{datetime: ~U[2026-10-12 00:00:00Z], value_ohlc: zero, has_changed: 0}
      ]

      assert [_, %{value_ohlc: %{open: 3.0, high: 3.0, low: 3.0, close: 3.0}}] =
               LabeledBalance.fill_gaps(rows)
    end

    test "no changes return no rows" do
      assert LabeledBalance.fill_gaps([%{datetime: @from, value: 0.0, has_changed: 0}]) == []
    end
  end

  describe "MetricAdapter with the delta source" do
    test "timeseries_data reads the view and fills the intervals without changes" do
      ids = ids_rows([{"ethereum", 1681}], [{@binance, 7, ""}])

      rows = [
        [1_791_504_000, 0.0, 0],
        [1_791_590_400, 3_293_032.5, 1],
        [1_791_676_800, 0.0, 0],
        [1_791_763_200, 3_290_000.0, 1]
      ]

      mock_clickhouse(ids, rows)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, data} =
                 MetricAdapter.timeseries_data(
                   "labelled_historical_balance",
                   %{slug: "ethereum"},
                   @from,
                   @to,
                   "1d",
                   additional_filters: [label_fqn: @binance],
                   source: :delta
                 )

        assert data == [
                 %{datetime: ~U[2026-10-10 00:00:00Z], value: 3_293_032.5},
                 %{datetime: ~U[2026-10-11 00:00:00Z], value: 3_293_032.5},
                 %{datetime: ~U[2026-10-12 00:00:00Z], value: 3_290_000.0}
               ]

        assert_received {:view_sql, sql}
        assert sql =~ "default.cumulative_labeled_balance("
        refute sql =~ "arrayZip"
      end)
    end

    test "timeseries_data rejects several labels for one asset" do
      ids = ids_rows([{"ethereum", 1681}], [{@binance, 7, ""}, {"santiment/coinbase:v1", 8, ""}])

      mock_clickhouse(ids, [])
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:error, error} =
                 MetricAdapter.timeseries_data(
                   "labelled_historical_balance",
                   %{slug: "ethereum"},
                   @from,
                   @to,
                   "1d",
                   additional_filters: [label_fqn: [@binance, "santiment/coinbase:v1"]],
                   source: :delta
                 )

        assert error =~ "Multiple labels per asset are not supported"
        refute_received {:view_sql, _}
      end)
    end

    test "timeseries_data with several slugs returns an error" do
      ids = ids_rows([{"ethereum", 1681}, {"chainlink", 1526}], [{@binance, 7, ""}])

      mock_clickhouse(ids, [])
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:error, error} =
                 MetricAdapter.timeseries_data(
                   "labelled_historical_balance",
                   %{slug: ["ethereum", "chainlink"]},
                   @from,
                   @to,
                   "1d",
                   additional_filters: [label_fqn: @binance],
                   source: :delta
                 )

        assert error =~ "use timeseriesDataPerSlug"
        refute_received {:view_sql, _}
      end)
    end

    test "timeseries_data with a one-element slug list works" do
      ids = ids_rows([{"ethereum", 1681}], [{@binance, 7, ""}])

      mock_clickhouse(ids, [[1_791_590_400, 1.0, 1]])
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, [%{value: 1.0}]} =
                 MetricAdapter.timeseries_data(
                   "labelled_historical_balance",
                   %{slug: ["ethereum"]},
                   @from,
                   @to,
                   "1d",
                   additional_filters: [label_fqn: @binance],
                   source: :delta
                 )
      end)
    end

    test "aggregated_timeseries_data splits more than 1000 assets in chunks" do
      slugs = Enum.map(1..1500, &"slug-#{&1}")
      assets = Enum.with_index(slugs, fn slug, i -> {slug, i + 1} end)
      ids = ids_rows(assets, [{@binance, 7, ""}])
      rows = [["slug-1", 5.0, 1]]

      mock_clickhouse(ids, rows)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, result} =
                 MetricAdapter.aggregated_timeseries_data(
                   "labelled_historical_balance",
                   %{slug: slugs},
                   @from,
                   @to,
                   additional_filters: [label_fqn: @binance],
                   source: :delta
                 )

        assert map_size(result) == 1500
        assert result["slug-1"] == 5.0
        assert result["slug-2"] == nil
      end)
    end

    test "the metadata queries use the delta metric" do
      assert LabeledBalance.metadata_metric(
               "labelled_historical_balance",
               %{slug: "ethereum"},
               source: :delta
             ) == "labelled_historical_balance_changes"

      assert LabeledBalance.metadata_metric(
               "labelled_historical_balance",
               %{slug: "ethereum"},
               source: :legacy
             ) == "labelled_historical_balance"

      assert LabeledBalance.metadata_metric("price_usd", %{slug: "ethereum"}, source: :delta) ==
               "price_usd"
    end

    test "timeseries_data_per_slug pairs the whale labels with their assets" do
      ids =
        ids_rows([{"ethereum", 1681}, {"chainlink", 1526}], [
          {"santiment/whale_usd_balance(ethereum):v1", 1, "ethereum"},
          {"santiment/whale_usd_balance(chainlink):v1", 2, "chainlink"}
        ])

      # Ordered by asset and time, like the query
      rows = [
        [1_791_590_400, "chainlink", 200.0, 1],
        [1_791_676_800, "chainlink", 0.0, 0],
        [1_791_590_400, "ethereum", 0.0, 0],
        [1_791_676_800, "ethereum", 100.0, 1]
      ]

      mock_clickhouse(ids, rows)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok,
                [
                  %{
                    datetime: ~U[2026-10-10 00:00:00Z],
                    data: [%{slug: "chainlink", value: 200.0}]
                  },
                  %{datetime: ~U[2026-10-11 00:00:00Z], data: data}
                ]} =
                 MetricAdapter.timeseries_data_per_slug(
                   "historical_balance_whales_usd",
                   %{slug: ["ethereum", "chainlink"]},
                   @from,
                   @to,
                   "1d",
                   source: :delta
                 )

        assert Enum.sort_by(data, & &1.slug) == [
                 %{slug: "chainlink", value: 200.0},
                 %{slug: "ethereum", value: 100.0}
               ]

        assert_received {:view_sql, sql}
        assert sql =~ "default.cumulative_labeled_balance("
        assert sql =~ "arrayZip"
      end)
    end

    test "aggregated_timeseries_data returns nil for slugs without data" do
      ids = ids_rows([{"bitcoin", 1452}, {"ethereum", 1681}], [{"santiment/fund:v1", 5, ""}])
      rows = [["bitcoin", 1_029_583.0, 1], ["ethereum", 0.0, 0]]

      mock_clickhouse(ids, rows)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, %{"bitcoin" => 1_029_583.0, "ethereum" => nil}} =
                 MetricAdapter.aggregated_timeseries_data(
                   "combined_historical_balance_funds",
                   %{slug: ["bitcoin", "ethereum"]},
                   @from,
                   @to,
                   source: :delta
                 )
      end)
    end

    test "owner metrics without a label return an error" do
      mock_clickhouse([], [])
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:error, error} =
                 MetricAdapter.timeseries_data(
                   "historical_balance_centralized_exchanges",
                   %{slug: "ethereum"},
                   @from,
                   @to,
                   "1d",
                   source: :delta
                 )

        assert error =~ "requires a 'labelFqn' or 'labelFqns'"
      end)
    end

    test "slugs_by_filter and slugs_order are not supported with *" do
      set_from_delta_slugs("*")

      assert {:error, error} =
               MetricAdapter.slugs_by_filter(
                 "labelled_historical_balance",
                 @from,
                 @to,
                 :greater_than,
                 10,
                 []
               )

      assert error =~ "not supported"

      assert {:error, _} =
               MetricAdapter.slugs_order("labelled_historical_balance", @from, @to, :desc, [])
    end
  end
end

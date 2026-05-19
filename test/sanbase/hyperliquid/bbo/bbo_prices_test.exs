defmodule Sanbase.Hyperliquid.Bbo.BboPricesTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Hyperliquid.Bbo.BboPrices
  alias Sanbase.Project.SourceSlugMapping

  setup do
    %{
      slug: "bitcoin",
      from: ~U[2026-05-07 00:00:00Z],
      to: ~U[2026-05-07 01:00:00Z],
      interval: "1m",
      t1: ~U[2026-05-07 00:00:00Z],
      t2: ~U[2026-05-07 00:01:00Z]
    }
  end

  test "computes mid_price and weighted_mid_price for two-sided rows", ctx do
    rows = [
      [DateTime.to_unix(ctx.t1), 100.0, 2.0, 102.0, 4.0],
      [DateTime.to_unix(ctx.t2), 200.0, 1.0, 204.0, 3.0]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, [r1, r2]} =
               BboPrices.timeseries_data(ctx.slug, ctx.from, ctx.to, ctx.interval)

      assert r1.datetime == ctx.t1
      assert r1.bid_price == 100.0
      assert r1.bid_volume == 2.0
      assert r1.ask_price == 102.0
      assert r1.ask_volume == 4.0
      assert r1.mid_price == 101.0
      # (100 * 4 + 102 * 2) / (2 + 4) = 604 / 6
      assert r1.weighted_mid_price == 604.0 / 6.0

      assert r2.datetime == ctx.t2
      assert r2.mid_price == 202.0
      # (200 * 3 + 204 * 1) / (1 + 3) = 804 / 4
      assert r2.weighted_mid_price == 804.0 / 4.0
    end)
  end

  test "returns nil mid/weighted_mid when bid side is missing", ctx do
    rows = [[DateTime.to_unix(ctx.t1), nil, nil, 102.0, 4.0]]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, [r]} =
               BboPrices.timeseries_data(ctx.slug, ctx.from, ctx.to, ctx.interval)

      assert r.bid_price == nil
      assert r.ask_price == 102.0
      assert r.mid_price == nil
      assert r.weighted_mid_price == nil
    end)
  end

  test "returns nil mid/weighted_mid when ask side is missing", ctx do
    rows = [[DateTime.to_unix(ctx.t1), 100.0, 2.0, nil, nil]]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, [r]} =
               BboPrices.timeseries_data(ctx.slug, ctx.from, ctx.to, ctx.interval)

      assert r.mid_price == nil
      assert r.weighted_mid_price == nil
    end)
  end

  test "returns nil weighted_mid when both volumes are 0", ctx do
    rows = [[DateTime.to_unix(ctx.t1), 100.0, 0.0, 102.0, 0.0]]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, [r]} =
               BboPrices.timeseries_data(ctx.slug, ctx.from, ctx.to, ctx.interval)

      assert r.mid_price == 101.0
      assert r.weighted_mid_price == nil
    end)
  end

  describe "k-prefix scaling" do
    defp seed_mapping(sanbase_slug, hyperliquid_coin) do
      project = insert(:project, %{slug: sanbase_slug})

      {:ok, _} =
        SourceSlugMapping.create(%{
          source: "hyperliquid",
          slug: hyperliquid_coin,
          project_id: project.id
        })

      :ok
    end

    test "divides price by 1000 and multiplies volume by 1000 when hyperliquid coin starts with lowercase k",
         ctx do
      seed_mapping("pepe", "kPEPE")
      rows = [[DateTime.to_unix(ctx.t1), 1000.0, 2000.0, 2000.0, 4000.0]]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, [r]} =
                 BboPrices.timeseries_data("pepe", ctx.from, ctx.to, ctx.interval)

        assert r.bid_price == 1.0
        assert r.bid_volume == 2_000_000.0
        assert r.ask_price == 2.0
        assert r.ask_volume == 4_000_000.0
        assert r.mid_price == 1.5
        # (1 * 4_000_000 + 2 * 2_000_000) / (2_000_000 + 4_000_000)
        assert r.weighted_mid_price == 8_000_000.0 / 6_000_000.0
      end)
    end

    test "notional is preserved across k-coin scaling", ctx do
      seed_mapping("pepe", "kPEPE")
      rows = [[DateTime.to_unix(ctx.t1), 0.003691, 202_527.0, 0.003692, 100_000.0]]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, [r]} =
                 BboPrices.timeseries_data("pepe", ctx.from, ctx.to, ctx.interval)

        assert_in_delta r.bid_price * r.bid_volume, 0.003691 * 202_527.0, 1.0e-6
        assert_in_delta r.ask_price * r.ask_volume, 0.003692 * 100_000.0, 1.0e-6
      end)
    end

    test "leaves values unchanged when hyperliquid coin has no k prefix", ctx do
      seed_mapping("bitcoin", "BTC")
      rows = [[DateTime.to_unix(ctx.t1), 100.0, 2.0, 102.0, 4.0]]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, [r]} =
                 BboPrices.timeseries_data("bitcoin", ctx.from, ctx.to, ctx.interval)

        assert r.bid_price == 100.0
        assert r.bid_volume == 2.0
        assert r.ask_price == 102.0
        assert r.ask_volume == 4.0
      end)
    end

    test "uppercase K prefix does not trigger scaling", ctx do
      seed_mapping("kava", "KAVA")
      rows = [[DateTime.to_unix(ctx.t1), 100.0, 2.0, 102.0, 4.0]]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, [r]} =
                 BboPrices.timeseries_data("kava", ctx.from, ctx.to, ctx.interval)

        assert r.bid_price == 100.0
        assert r.ask_price == 102.0
      end)
    end

    test "missing source_slug_mapping leaves values unchanged", ctx do
      rows = [[DateTime.to_unix(ctx.t1), 100.0, 2.0, 102.0, 4.0]]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, [r]} =
                 BboPrices.timeseries_data("unmapped", ctx.from, ctx.to, ctx.interval)

        assert r.bid_price == 100.0
        assert r.ask_price == 102.0
      end)
    end

    test "scaled k-coin preserves nil sides", ctx do
      seed_mapping("pepe", "kPEPE")
      rows = [[DateTime.to_unix(ctx.t1), nil, nil, 2000.0, 4000.0]]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, [r]} =
                 BboPrices.timeseries_data("pepe", ctx.from, ctx.to, ctx.interval)

        assert r.bid_price == nil
        assert r.bid_volume == nil
        assert r.ask_price == 2.0
        assert r.ask_volume == 4_000_000.0
        assert r.mid_price == nil
        assert r.weighted_mid_price == nil
      end)
    end
  end
end

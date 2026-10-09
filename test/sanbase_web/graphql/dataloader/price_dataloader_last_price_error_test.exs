defmodule SanbaseWeb.Graphql.PriceDataloaderLastPriceErrorTest do
  # Reproduces SANBASE-BACKEND-PROD-M8:
  #   MatchError: no match of right hand side value: {:error, "[...] The query took too
  #   long to complete. ..."} in SanbaseWeb.Graphql.PriceDataloader.query/3
  #
  # `PriceDataloader.query(:last_price_usd, ..)` hard-matches
  # `{:ok, result} = Sanbase.Metric.aggregated_timeseries_data(...)`. A ClickHouse
  # error/timeout raises inside the Dataloader.KV batch task, which crashes (one Sentry
  # event per occurrence) instead of degrading to "no price".
  #
  # Desired behaviour: the batch function does not raise; slugs without a price resolve
  # to nil (the consumers - `balance_usd` and `usd_balance` - already handle nil).
  use Sanbase.DataCase, async: false

  alias SanbaseWeb.Graphql.PriceDataloader

  @error_msg "[df8aea28-9850-48d2-9a28-70bc85153a82] The query took too long to complete."

  @tag capture_log: true
  test "last_price_usd does not raise when the price query fails" do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      {:error, @error_msg}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try do
          {:ok, PriceDataloader.query(:last_price_usd, ["bitcoin", "ethereum"], nil)}
        rescue
          e -> {:raised, e}
        end

      assert {:ok, map} = result
      assert is_map(map)

      for slug <- ["bitcoin", "ethereum"] do
        value = Map.get(map, slug)
        assert is_nil(value) or match?({:error, _}, value)
      end
    end)
  end

  test "last_price_usd still returns the prices on success" do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      {:ok, %{"bitcoin" => 31_886.79, "ethereum" => 1_800.5}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert %{"bitcoin" => 31_886.79, "ethereum" => 1_800.5} =
               PriceDataloader.query(:last_price_usd, ["bitcoin", "ethereum"], nil)
    end)
  end
end

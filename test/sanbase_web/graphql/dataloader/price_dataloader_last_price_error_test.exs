defmodule SanbaseWeb.Graphql.PriceDataloaderLastPriceErrorTest do
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
      assert PriceDataloader.query(:last_price_usd, ["bitcoin", "ethereum"], nil) == %{
               "bitcoin" => {:error, @error_msg},
               "ethereum" => {:error, @error_msg}
             }
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

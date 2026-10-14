defmodule SanbaseWeb.Graphql.PriceDataloaderLastPriceErrorTest do
  use Sanbase.DataCase, async: false

  alias SanbaseWeb.Graphql.PriceDataloader

  @error_msg "The query took too long to complete."

  test "a failed last_price_usd query is an error for every slug instead of raising" do
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
end

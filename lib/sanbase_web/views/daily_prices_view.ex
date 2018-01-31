defmodule SanbaseWeb.DailyPricesView do
  use SanbaseWeb, :view

  def render("index.json", %{prices: prices}) do
    prices
    |> Enum.map(fn {pair, data} ->
      {
        pair,
        convert_to_price_array(data)
      }
    end)
    |> Map.new()
  end

  defp convert_to_price_array(data) do
    data
    |> Enum.map(fn [_date, avg_price | _tail] -> avg_price end)
  end
end

defmodule SanbaseWeb.DailyPricesView do
  use SanbaseWeb, :view

  def render("index.json", %{prices: prices}) do
    prices
  end
end

defmodule SanbaseWeb.Graphql.PriceStore do
  alias Sanbase.Prices

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(pair, ids) when is_list(ids) do
    ids
    |> Enum.uniq()
    |> Enum.map(fn id ->
      {id, fetch_price(pair, id)}
    end)
    |> Map.new()
  end

  # Helper functions

  defp fetch_price(pair, :last) do
    with {:ok, {_dt, price, _mcap, _volume}} <- Prices.Store.last_record(pair) do
      Decimal.new(price)
    else
      _error -> nil
    end
  end

  defp fetch_price(pair, %{from: from, to: to, interval: interval}) do
    Prices.Store.fetch_prices_with_resolution(pair, from, to, interval)
  end
end

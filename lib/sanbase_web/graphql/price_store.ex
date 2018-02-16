defmodule SanbaseWeb.Graphql.PriceStore do
  alias Sanbase.Prices

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def fetch_price(pair, :last) do
    {_dt, price, _, _} = Prices.Store.last_record(pair)

    Decimal.new(price)
  end

  def fetch_price(pair, %{from: from, to: to, interval: interval}) do
    Prices.Store.fetch_prices_with_resolution(pair, from, to, interval)
  end

  def query(pair, ids) when is_list(ids) do
    ids
    |> Enum.uniq()
    |> Enum.map(fn id ->
      {id, fetch_price(pair, id)}
    end)
    |> Map.new()
  end
end

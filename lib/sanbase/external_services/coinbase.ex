defmodule Sanbase.ExternalServices.Coinbase do
  use Tesla

  plug Tesla.Middleware.Tuples
  plug Tesla.Middleware.JSON

  def get_eth_price do
    response = get("https://api.coinbase.com/v2/prices/ETH-USD/sell")

    case response do
      {:ok, resp} ->
        if resp.status >= 200 and resp.status < 300 do
          case Float.parse(resp.body["data"]["amount"]) do
            {eth_price, _} -> eth_price
            _ -> nil
          end
        else
          nil
        end
      _ -> nil
    end
  end
end

defmodule Sanbase.ExternalServices do
  use Tesla

  plug Tesla.Middleware.Tuples
  plug Tesla.Middleware.JSON

  def get_eth_price do
    response = get("https://api.coinbase.com/v2/prices/ETH-USD/sell")

    case response do
      {:ok, env} ->
        if env.status >= 200 and env.status < 300 do
          case Float.parse(env.body["data"]["amount"]) do
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

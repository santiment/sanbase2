defmodule Sanbase.ExternalServices.Coinmarketcap.PricePoint do
  defstruct [:datetime, :marketcap, :price_usd, :volume_usd, :price_btc, :volume_btc]
end

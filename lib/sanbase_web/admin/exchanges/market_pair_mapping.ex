defmodule Sanbase.ExAdmin.Exchanges.MarketPairMapping do
  use ExAdmin.Register

  register_resource Sanbase.Exchanges.MarketPairMapping do
    show _mapping do
      attributes_table(all: true)
    end
  end
end

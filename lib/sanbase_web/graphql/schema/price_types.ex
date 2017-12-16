defmodule SanbaseWeb.Graphql.PriceTypes do
  alias SanbaseWeb.Graphql.PriceResolver

  use Absinthe.Schema.Notation

  object :price_point do
    field :datetime, non_null(:datetime)
    field :marketcap, :integer
    field :price_usd, :string
    field :price_btc, :string
    field :volume, :integer
  end

end

defmodule SanbaseWeb.Graphql.MarketSegmentTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :market_segment do
    field(:name, :string)
    field(:count, :integer)
  end
end

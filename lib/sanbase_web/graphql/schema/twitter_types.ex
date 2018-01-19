defmodule SanbaseWeb.Graphql.TwitterTypes do
  use Absinthe.Schema.Notation

  object :twitter_data do
    field(:datetime, non_null(:datetime))
    field(:twitter_name, :string)
    field(:followers_count, :integer)
    field(:ticker, :string)
  end
end
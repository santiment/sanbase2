defmodule SanbaseWeb.Graphql.TwitterTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :twitter_data do
    field(:datetime, non_null(:datetime))
    field(:followers_count, :integer)
  end
end

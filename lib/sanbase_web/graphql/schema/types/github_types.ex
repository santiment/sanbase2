defmodule SanbaseWeb.Graphql.GithubTypes do
  use Absinthe.Schema.Notation

  input_object :selector do
    field(:slug, :string)
    field(:market_segments, list_of(:string))
  end

  object :activity_point do
    field(:datetime, non_null(:datetime))
    field(:activity, non_null(:integer))
  end
end

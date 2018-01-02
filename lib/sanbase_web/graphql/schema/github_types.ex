defmodule SanbaseWeb.Graphql.GithubTypes do
  use Absinthe.Schema.Notation

  object :activity_point do
    field(:datetime, non_null(:datetime))
    field(:activity, non_null(:integer))
  end
end
defmodule SanbaseWeb.Graphql.GithubTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  input_object :github_organizations_selector do
    field(:slug, :string)
    field(:market_segments, list_of(:string))
    field(:organizations, list_of(:string))
  end

  object :activity_point do
    field(:datetime, non_null(:datetime))
    field(:activity, non_null(:float))
  end
end

defmodule SanbaseWeb.Graphql.TagTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :tag do
    field(:name, non_null(:string))
  end
end

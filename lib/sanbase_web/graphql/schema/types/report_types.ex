defmodule SanbaseWeb.Graphql.ReportTypes do
  use Absinthe.Schema.Notation

  object :report do
    field(:url, :string)
    field(:name, non_null(:string))
    field(:description, :string)
    field(:tags, list_of(:string))
    field(:is_pro, non_null(:boolean))
    field(:inserted_at, :datetime)
  end
end

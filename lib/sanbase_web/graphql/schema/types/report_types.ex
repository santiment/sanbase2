defmodule SanbaseWeb.Graphql.ReportTypes do
  use Absinthe.Schema.Notation

  object :report do
    field(:url, :string)
    field(:name, :string)
    field(:description, :string)
    field(:tags, list_of(:string))
    field(:is_pro, :boolean)
  end
end

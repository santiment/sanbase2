defmodule SanbaseWeb.Graphql.SheetsTemplateTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :sheets_template do
    field(:url, :string)
    field(:name, non_null(:string))
    field(:description, :string)
    field(:is_pro, non_null(:boolean))
  end
end

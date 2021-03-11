defmodule SanbaseWeb.Graphql.SheetsTemplateTypes do
  use Absinthe.Schema.Notation

  object :sheets_template do
    field(:url, :string)
    field(:name, :string)
    field(:description, :string)
    field(:is_pro, :boolean)
  end
end

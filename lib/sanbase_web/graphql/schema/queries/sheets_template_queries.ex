defmodule SanbaseWeb.Graphql.Schema.SheetsTemplateQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.SheetsTemplateResolver

  object :sheets_template_queries do
    @desc ~s"""
    List all sheets templates.
    """
    field :get_sheets_templates, list_of(:sheets_template) do
      meta(access: :free)

      resolve(&SheetsTemplateResolver.get_sheets_templates/3)
    end
  end
end

defmodule SanbaseWeb.Graphql.Schema.ReportQueries do
  use Absinthe.Schema.Notation
  alias SanbaseWeb.Graphql.Resolvers.ReportResolver

  # import_types(SanbaseWeb.Graphql.Schema.ReportTypes)

  object :report_data do
    field(:url, :string)
    field(:name, :string)
    field(:descrption, :string)
  end

  object :report_queries do
    @desc ~s"""

    """
    field :list_reports, :report_data do
      # middleware(JWTAuth)

      resolve(&ReportResolver.list_reports/3)
    end
  end

  object :report_mutations do
    @desc ~s"""

    """
    field :upload_report, :string do
      arg(:report, non_null(:upload))
      arg(:name, :string)
      arg(:descrption, :string)

      # arg :metadata, :upload

      middleware(BasicAuth)

      resolve(&ReportResolver.upload_report/3)
    end
  end
end

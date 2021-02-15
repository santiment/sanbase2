defmodule SanbaseWeb.Graphql.Schema.ReportQueries do
  use Absinthe.Schema.Notation
  alias SanbaseWeb.Graphql.Resolvers.ReportResolver
  alias SanbaseWeb.Graphql.Middlewares.BasicAuth

  object :report_queries do
    @desc ~s"""
    List all reports.
    """
    field :get_reports, list_of(:report) do
      resolve(&ReportResolver.get_reports/3)
    end

    @desc ~s"""
    Get all reports by asset tags.
    """
    field :get_reports_by_tags, list_of(:report) do
      arg(:tags, non_null(list_of(:string)))

      resolve(&ReportResolver.get_reports_by_tags/3)
    end
  end

  object :report_mutations do
    @desc ~s"""
    Upload a report file.
    """
    field :upload_report, :report do
      arg(:report, non_null(:upload))
      arg(:name, non_null(:string))
      arg(:description, :string)

      middleware(BasicAuth)

      resolve(&ReportResolver.upload_report/3)
    end
  end
end

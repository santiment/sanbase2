defmodule SanbaseWeb.Graphql.Schema.ProjectQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.{
    PriceResolver,
    ProjectResolver,
    ProjectTransactionsResolver
  }

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.{TimeframeRestriction, ProjectPermissions}

  import_types(SanbaseWeb.Graphql.ProjectTypes)

  object :project_queries do
    @desc "Fetch all projects that have price data."
    field :all_projects, list_of(:project) do
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:min_volume, :integer)

      middleware(ProjectPermissions)
      cache_resolve(&ProjectResolver.all_projects/3)
    end

    @desc "Fetch all ERC20 projects."
    field :all_erc20_projects, list_of(:project) do
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:min_volume, :integer)

      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_erc20_projects/3)
    end

    @desc "Fetch all currency projects. A currency project is a project that has price data but is not classified as ERC20."
    field :all_currency_projects, list_of(:project) do
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:min_volume, :integer)

      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_currency_projects/3)
    end

    field :all_projects_by_function, list_of(:project) do
      arg(:function, :json)

      middleware(ProjectPermissions)

      cache_resolve(&ProjectResolver.all_projects_by_function/3)
    end

    @desc "Fetch all project transparency projects. This query requires basic authentication."
    field :all_projects_project_transparency, list_of(:project) do
      middleware(BasicAuth)
      resolve(&ProjectResolver.all_projects_project_transparency/3)
    end

    @desc "Return the number of projects in each"

    @desc "Fetch a project by its ID."
    field :project, :project do
      arg(:id, non_null(:id))
      resolve(&ProjectResolver.project/3)
    end

    @desc "Fetch a project by a unique identifier."
    field :project_by_slug, :project do
      arg(:slug, non_null(:string))
      cache_resolve(&ProjectResolver.project_by_slug/3)
    end

    @desc ~s"""
    Fetch data for each of the projects in the slugs lists
    """
    field :projects_list_stats, list_of(:project_stats) do
      arg(:slugs, non_null(list_of(:string)))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})
      cache_resolve(&PriceResolver.multiple_projects_stats/3)
    end

    @desc "Returns the number of erc20 projects, currency projects and all projects"
    field :projects_count, :projects_count do
      arg(:min_volume, :integer)
      cache_resolve(&ProjectResolver.projects_count/3)
    end

    @desc ~s"""
    Fetch data bucketed by interval. The returned marketcap and volume are the sum
    of the marketcaps and volumes of all projects for that given time interval
    """
    field :projects_list_history_stats, list_of(:combined_projects_stats) do
      arg(:slugs, non_null(list_of(:string)))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string), default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})
      cache_resolve(&ProjectResolver.combined_history_stats/3)
    end

    field :available_metrics_for_project, list_of(:string) do
      arg(:slug, non_null(:string))

      cache_resolve(&ProjectResolver.available_metrics_for_project/3)
    end
  end

  object :project_eth_spent_queries do
    @desc "Fetch the ETH spent by all projects within a given time period."
    field :eth_spent_by_all_projects, :float do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})

      cache_resolve(&ProjectTransactionsResolver.eth_spent_by_all_projects/3,
        ttl: 600,
        max_ttl_offset: 240
      )
    end

    @desc "Fetch the ETH spent by all ERC20 projects within a given time period."
    field :eth_spent_by_erc20_projects, :float do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})

      cache_resolve(&ProjectTransactionsResolver.eth_spent_by_erc20_projects/3,
        ttl: 600,
        max_ttl_offset: 240
      )
    end

    @desc ~s"""
    Fetch ETH spent by all projects within a given time period and interval.
    This query returns a list of values where each value is of length `interval`.
    """
    field :eth_spent_over_time_by_erc20_projects, list_of(:eth_spent_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})

      cache_resolve(&ProjectTransactionsResolver.eth_spent_over_time_by_erc20_projects/3,
        ttl: 600,
        max_ttl_offset: 240
      )
    end

    @desc ~s"""
    Fetch ETH spent by all projects within a given time period and interval.
    This query returns a list of values where each value is of length `interval`.
    """
    field :eth_spent_over_time_by_all_projects, list_of(:eth_spent_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true, allow_realtime_data: true})

      cache_resolve(&ProjectTransactionsResolver.eth_spent_over_time_by_all_projects/3,
        ttl: 600,
        max_ttl_offset: 240
      )
    end
  end
end

defmodule SanbaseWeb.Graphql.Schema.ChangelogQueries do
  @moduledoc """
  Queries for changelog-related data for metrics and assets.
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.ChangelogResolver

  object :changelog_queries do
    @desc """
    Get changelog for metrics with support for both infinite scrolling and traditional pagination.
    Returns a list of dates with created and deprecated metrics for each date.

    Example:
    query {
      metricsChangelog(page: 1, pageSize: 20, searchTerm: "price") {
        entries {
          date
          createdMetrics {
            metric {
              humanReadableName
              metric
              docs {
                link
              }
            }
            eventTimestamp
          }
          deprecatedMetrics {
            metric {
              humanReadableName
              metric
            }
            eventTimestamp
            deprecationNote
          }
        }
        pagination {
          hasMore
          currentPage
          totalDates
          totalPages
        }
      }
    }
    """
    field :metrics_changelog, :metrics_changelog_result do
      meta(access: :free)

      @desc "Page number (starts from 1)"
      arg(:page, :integer, default_value: 1)

      @desc "Number of date entries per page"
      arg(:page_size, :integer, default_value: 20)

      @desc "Search term to filter metrics by name or technical identifier"
      arg(:search_term, :string)

      cache_resolve(&ChangelogResolver.metrics_changelog/3, ttl: 300, max_ttl_offset: 60)
    end

    @desc """
    Get changelog for assets (projects) with support for regular pagination.
    Returns a list of dates with created and hidden assets for each date.

         Example:
     query {
       assetsChangelog(page: 1, pageSize: 10, searchTerm: "bitcoin") {
         entries {
           date
           createdAssets {
             asset {
               name
               ticker
               slug
               logoUrl
               description
               link
             }
             eventTimestamp
           }
           hiddenAssets {
             asset {
               name
               ticker
               slug
             }
             eventTimestamp
             hidingReason
           }
         }
         pagination {
           hasMore
           totalDates
           currentPage
           totalPages
         }
       }
     }
    """
    field :assets_changelog, :assets_changelog_result do
      meta(access: :free)

      @desc "Page number (starts from 1)"
      arg(:page, :integer, default_value: 1)

      @desc "Number of date entries per page"
      arg(:page_size, :integer, default_value: 10)

      @desc "Search term to filter assets by name or ticker"
      arg(:search_term, :string)

      cache_resolve(&ChangelogResolver.assets_changelog/3, ttl: 300, max_ttl_offset: 60)
    end
  end
end

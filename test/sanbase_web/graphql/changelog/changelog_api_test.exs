defmodule SanbaseWeb.Graphql.ChangelogApiTest do
  use SanbaseWeb.ConnCase, async: false

  test "get metrics changelog", context do
    query = """
    {
      metricsChangelog(page: 1, pageSize: 5) {
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
          totalDates
          currentPage
          totalPages
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert %{"data" => %{"metricsChangelog" => changelog}} = result
    assert is_map(changelog)
    assert Map.has_key?(changelog, "entries")
    assert Map.has_key?(changelog, "pagination")
    assert is_list(changelog["entries"])
    assert is_map(changelog["pagination"])
    assert Map.has_key?(changelog["pagination"], "hasMore")
  end

  test "get assets changelog", context do
    query = """
    {
      assetsChangelog(page: 1, pageSize: 5) {
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

    result =
      context.conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert %{"data" => %{"assetsChangelog" => changelog}} = result
    assert is_map(changelog)
    assert Map.has_key?(changelog, "entries")
    assert Map.has_key?(changelog, "pagination")
    assert is_list(changelog["entries"])
    assert is_map(changelog["pagination"])
    assert Map.has_key?(changelog["pagination"], "hasMore")
    assert Map.has_key?(changelog["pagination"], "totalDates")
    assert Map.has_key?(changelog["pagination"], "currentPage")
    assert Map.has_key?(changelog["pagination"], "totalPages")
  end

  test "metrics changelog with search term", context do
    query = """
    {
      metricsChangelog(page: 1, pageSize: 5, searchTerm: "price") {
        entries {
          date
          createdMetrics {
            metric {
              humanReadableName
              metric
            }
          }
        }
        pagination {
          hasMore
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert %{"data" => %{"metricsChangelog" => changelog}} = result
    assert is_map(changelog)
    assert Map.has_key?(changelog, "entries")
    assert is_list(changelog["entries"])
  end

  test "assets changelog with search term", context do
    query = """
    {
      assetsChangelog(page: 1, pageSize: 5, searchTerm: "bitcoin") {
        entries {
          date
          createdAssets {
            asset {
              name
              ticker
              slug
            }
          }
        }
        pagination {
          hasMore
          totalDates
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert %{"data" => %{"assetsChangelog" => changelog}} = result
    assert is_map(changelog)
    assert Map.has_key?(changelog, "entries")
    assert is_list(changelog["entries"])
  end

  test "metrics changelog pagination - page 1", context do
    query = """
    {
      metricsChangelog(page: 1, pageSize: 2) {
        entries {
          date
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

    result =
      context.conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert %{"data" => %{"metricsChangelog" => changelog}} = result
    pagination = changelog["pagination"]

    assert pagination["currentPage"] == 1
    assert is_boolean(pagination["hasMore"])
    assert length(changelog["entries"]) <= 2
    assert is_integer(pagination["totalDates"]) or pagination["totalDates"] == 0
    assert is_integer(pagination["totalPages"]) or pagination["totalPages"] == 0
  end

  test "metrics changelog pagination - page 2", context do
    query = """
    {
      metricsChangelog(page: 2, pageSize: 2) {
        entries {
          date
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

    result =
      context.conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert %{"data" => %{"metricsChangelog" => changelog}} = result
    pagination = changelog["pagination"]

    assert pagination["currentPage"] == 2
    assert is_boolean(pagination["hasMore"])
    assert length(changelog["entries"]) <= 2
    assert is_integer(pagination["totalDates"]) or pagination["totalDates"] == 0
    assert is_integer(pagination["totalPages"]) or pagination["totalPages"] == 0
  end

  test "assets changelog pagination - different page sizes", context do
    # Test with page size 1
    query1 = """
    {
      assetsChangelog(page: 1, pageSize: 1) {
        entries {
          date
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

    result1 =
      context.conn
      |> post("/graphql", %{"query" => query1})
      |> json_response(200)

    # Test with page size 3
    query3 = """
    {
      assetsChangelog(page: 1, pageSize: 3) {
        entries {
          date
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

    result3 =
      context.conn
      |> post("/graphql", %{"query" => query3})
      |> json_response(200)

    assert %{"data" => %{"assetsChangelog" => changelog1}} = result1
    assert %{"data" => %{"assetsChangelog" => changelog3}} = result3

    # Verify pagination info is correct
    assert changelog1["pagination"]["currentPage"] == 1
    assert changelog3["pagination"]["currentPage"] == 1
    assert length(changelog1["entries"]) <= 1
    assert length(changelog3["entries"]) <= 3

    # Total dates should be the same regardless of page size
    if changelog1["pagination"]["totalDates"] && changelog3["pagination"]["totalDates"] do
      assert changelog1["pagination"]["totalDates"] == changelog3["pagination"]["totalDates"]
    end
  end

  test "metrics changelog - default pagination values", context do
    query = """
    {
      metricsChangelog {
        entries {
          date
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

    result =
      context.conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert %{"data" => %{"metricsChangelog" => changelog}} = result
    pagination = changelog["pagination"]

    # Should default to page 1
    assert pagination["currentPage"] == 1
    # Should respect default page size (20)
    assert length(changelog["entries"]) <= 20
    # Should now have totalDates and totalPages
    assert is_integer(pagination["totalDates"]) or pagination["totalDates"] == 0
    assert is_integer(pagination["totalPages"]) or pagination["totalPages"] == 0
  end

  test "assets changelog - default pagination values", context do
    query = """
    {
      assetsChangelog {
        entries {
          date
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

    result =
      context.conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert %{"data" => %{"assetsChangelog" => changelog}} = result
    pagination = changelog["pagination"]

    # Should default to page 1, pageSize 10
    assert pagination["currentPage"] == 1
    assert length(changelog["entries"]) <= 10
    assert is_boolean(pagination["hasMore"])

    if pagination["totalPages"] do
      assert pagination["totalPages"] >= 1 or pagination["totalPages"] == 0
    end
  end
end

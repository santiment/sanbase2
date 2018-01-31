defmodule SanbaseWeb.Graphql.ProjectApiPublicTest do
  use SanbaseWeb.ConnCase

  import SanbaseWeb.Graphql.TestHelpers

  test "public project listing forbidden fields", context do
    query = """
    {
      allProjects {
        id,
        ethBalance,
        btcBalance,
        roiUsd,
        fundsRaisedIcos {
          amount,
          currencyCode
        },
        initialIco {
          id
        },
        icos {
          id
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allProjects"))

    [error | _] = json_response(result, 400)["errors"]
    assert String.contains?(error["message"], "Cannot query field")
  end

  test "public project forbidden fields", context do
    query = """
    {
      project(id:$id)
      {
        id,
        initialIco {
          id
        },
        icos {
          id
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "project", "($id:ID!)", "{\"id\": 1}"))

    [error | _] = json_response(result, 400)["errors"]
    assert String.contains?(error["message"], "Cannot query field")
  end
end

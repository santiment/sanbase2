defmodule SanbaseWeb.Graphql.ProjectApiForbiddenFieldsTest do
  use SanbaseWeb.ConnCase, async: false

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

    [error | _] = json_response(result, 200)["errors"]

    assert error["message"] ==
             "Cannot query [\"initialIco\", \"icos\", \"fundsRaisedIcos\"] on a query that returns more than 1 project."
  end
end

defmodule SanbaseWeb.Graphql.Phase.Document.Validation.MaxDepthTest do
  use SanbaseWeb.ConnCase, async: false

  @max_depth 15

  # Build an introspection query whose selection nesting is exactly `depth`.
  # Shape: { __schema { types { fields { type { ofType { ... { name } } } } } } }
  # Top-level `__schema` counts as depth 1; every nested field adds 1; the leaf
  # scalar `name` ends at `depth`.
  defp nested_query(depth) when depth >= 2 do
    # 4 levels before the ofType chain: __schema, types, fields, type
    # then `depth - 4 - 1` ofType wrappers, then `name` as the scalar at `depth`.
    of_type_levels = depth - 5
    opens = String.duplicate("ofType { ", of_type_levels)
    closes = String.duplicate(" }", of_type_levels)

    """
    query {
      __schema {
        types {
          fields {
            type {
              #{opens}name#{closes}
            }
          }
        }
      }
    }
    """
  end

  # Same shape as `nested_query/1` but the inner chain lives inside a named
  # fragment, so the walker must resolve the spread to measure true depth.
  # Before the fix, the spread was treated as a leaf and this query was
  # mis-measured as depth 2.
  defp fragment_query(depth) when depth >= 2 do
    of_type_levels = depth - 5
    opens = String.duplicate("ofType { ", of_type_levels)
    closes = String.duplicate(" }", of_type_levels)

    """
    query {
      __schema {
        ...SchemaFrag
      }
    }

    fragment SchemaFrag on __Schema {
      types {
        fields {
          type {
            #{opens}name#{closes}
          }
        }
      }
    }
    """
  end

  test "query at max depth is accepted by the depth phase", %{conn: conn} do
    conn = post(conn, "/graphql", %{"query" => nested_query(@max_depth)})
    errors = json_response(conn, 200)["errors"] || []

    refute Enum.any?(errors, &String.contains?(&1["message"] || "", "maximum nesting depth"))
  end

  test "query exceeding max depth is rejected", %{conn: conn} do
    conn = post(conn, "/graphql", %{"query" => nested_query(@max_depth + 1)})

    assert %{"errors" => errors} = json_response(conn, 200)
    assert Enum.any?(errors, &String.contains?(&1["message"], "maximum nesting depth of 15"))
  end

  test "named fragment spread cannot bypass the depth cap", %{conn: conn} do
    conn = post(conn, "/graphql", %{"query" => fragment_query(@max_depth + 1)})

    assert %{"errors" => errors} = json_response(conn, 200)
    assert Enum.any?(errors, &String.contains?(&1["message"], "maximum nesting depth of 15"))
  end

  test "cyclic fragment graph terminates without stack overflow", %{conn: conn} do
    # F1 -> F2 -> F1 with finite inline nesting in each. The walker must mark
    # visited fragments; otherwise this recurses until the process dies.
    query = """
    query {
      __schema {
        ...F1
      }
    }

    fragment F1 on __Schema {
      types {
        ...F2
      }
    }

    fragment F2 on __Type {
      fields {
        type {
          ...F1
        }
      }
    }
    """

    # Must return a response at all (no timeout / crash). We don't assert on
    # accept vs reject — only that the phase terminates.
    conn = post(conn, "/graphql", %{"query" => query})
    assert is_map(json_response(conn, 200))
  end
end

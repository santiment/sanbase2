defmodule SanbaseWeb.Graphql.Phase.Document.Validation.ProvidedNonNullArgumentsInFragmentsTest do
  use SanbaseWeb.ConnCase, async: false

  defp post_query(conn, query) do
    conn
    |> post("/graphql", %{"query" => query})
    |> json_response(200)
  end

  test "a named fragment missing required arguments returns validation errors", %{conn: conn} do
    query = """
    {
      getMetric(metric: "price_usd") { ...MetricFields }
    }

    fragment MetricFields on Metric {
      timeseriesData(slug: "bitcoin") { value }
    }
    """

    %{"errors" => errors} = post_query(conn, query)
    messages = Enum.map(errors, & &1["message"])

    assert ~s(In argument "from": Expected type "DateTime!", found null.) in messages
    assert ~s(In argument "to": Expected type "DateTime!", found null.) in messages
  end

  test "an inline field missing required arguments still returns the same errors", %{conn: conn} do
    query = """
    {
      getMetric(metric: "price_usd") { timeseriesData(slug: "bitcoin") { value } }
    }
    """

    %{"errors" => errors} = post_query(conn, query)
    messages = Enum.map(errors, & &1["message"])

    assert ~s(In argument "from": Expected type "DateTime!", found null.) in messages
  end

  test "a named fragment with all required arguments passes validation", %{conn: conn} do
    query = """
    {
      getMetric(metric: "price_usd") { ...MetricFields }
    }

    fragment MetricFields on Metric {
      timeseriesData(slug: "bitcoin", from: "utc_now-1d", to: "utc_now") { value }
    }
    """

    result = post_query(conn, query)
    messages = Enum.map(result["errors"] || [], & &1["message"])

    refute Enum.any?(messages, &String.contains?(&1, "Expected type"))
  end
end

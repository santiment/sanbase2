defmodule SanbaseWeb.Graphql.FoundersSocialDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  test "successfully fetch social volume and sentiment for founders", context do
    # This test does not include treatWordAsLuceneQuery: true, so the
    # words are lowercased before being send and in the response
    body =
      Jason.encode!(%{
        "data" => %{"2024-09-28T00:00:00Z" => 373, "2024-09-29T00:00:00Z" => 487, "2024-09-30T00:00:00Z" => 323}
      })

    resp = %HTTPoison.Response{status_code: 200, body: body}

    HTTPoison
    |> Sanbase.Mock.prepare_mock(:get, fn _url, _headers, options ->
      search_texts =
        options[:params]
        |> Map.new()
        |> Map.get("founders")

      # Assert that the words are lowercased before they are sent
      assert search_texts == "vitalik,satoshi"

      {:ok, resp}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      for metric <- ["social_volume_total", "sentiment_positive_total"] do
        query = """
        {
          getMetric(metric: "#{metric}"){
            timeseriesData(
              selector: { founders: ["vitalik", "satoshi"] }
              from: "2024-09-28T00:00:00Z"
              to: "2024-09-30T00:00:00Z"
              interval: "1d"
            ){
              datetime
              value
            }
          }
        }
        """

        result =
          context.conn
          |> post("/graphql", query_skeleton(query))
          |> json_response(200)

        assert result == %{
                 "data" => %{
                   "getMetric" => %{
                     "timeseriesData" => [
                       %{"datetime" => "2024-09-28T00:00:00Z", "value" => 373.0},
                       %{"datetime" => "2024-09-29T00:00:00Z", "value" => 487.0},
                       %{"datetime" => "2024-09-30T00:00:00Z", "value" => 323.0}
                     ]
                   }
                 }
               }
      end
    end)
  end
end

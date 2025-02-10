defmodule SanbaseWeb.Graphql.WordsSocialVolumeApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  test "successfully fetch words social volume", context do
    # This test does not include treatWordAsLuceneQuery: true, so the
    # words are lowercased before being send and in the response
    body =
      Jason.encode!(%{
        "data" => %{
          "btc" => %{"2024-09-28T00:00:00Z" => 373, "2024-09-29T00:00:00Z" => 487, "2024-09-30T00:00:00Z" => 323},
          "eth or nft" => %{
            "2024-09-28T00:00:00Z" => 1681,
            "2024-09-29T00:00:00Z" => 3246,
            "2024-09-30T00:00:00Z" => 1577
          }
        }
      })

    resp = %HTTPoison.Response{status_code: 200, body: body}

    HTTPoison
    |> Sanbase.Mock.prepare_mock(:post, fn _url, body, _headers, _options ->
      search_texts =
        body
        |> Jason.decode!()
        |> Map.get("search_texts")

      # Assert that the words are lowercased before they are sent
      assert search_texts == "eth or nft,btc"

      {:ok, resp}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        wordsSocialVolume(
          selector: { words: ["eth OR nft", "btc"] }
          from: "2024-09-28T00:00:00Z"
          to: "2024-09-30T00:00:00Z"
          interval: "1d"
        ){
          word
          timeseriesData{
            datetime
            mentionsCount
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
                 "wordsSocialVolume" => [
                   %{
                     "timeseriesData" => [
                       %{"datetime" => "2024-09-28T00:00:00Z", "mentionsCount" => 373},
                       %{"datetime" => "2024-09-29T00:00:00Z", "mentionsCount" => 487},
                       %{"datetime" => "2024-09-30T00:00:00Z", "mentionsCount" => 323}
                     ],
                     "word" => "btc"
                   },
                   %{
                     "timeseriesData" => [
                       %{"datetime" => "2024-09-28T00:00:00Z", "mentionsCount" => 1681},
                       %{"datetime" => "2024-09-29T00:00:00Z", "mentionsCount" => 3246},
                       %{"datetime" => "2024-09-30T00:00:00Z", "mentionsCount" => 1577}
                     ],
                     "word" => "eth OR nft"
                   }
                 ]
               }
             }
    end)
  end

  test "successfully fetch words social volume - treatWordAsLuceneQuery: true", context do
    # This test does not include treatWordAsLuceneQuery: true, so the
    # words are lowercased before being send and in the response
    body =
      Jason.encode!(%{
        "data" => %{
          "BTC" => %{"2024-09-28T00:00:00Z" => 373, "2024-09-29T00:00:00Z" => 487, "2024-09-30T00:00:00Z" => 323},
          "eth OR nft" => %{
            "2024-09-28T00:00:00Z" => 1681,
            "2024-09-29T00:00:00Z" => 3246,
            "2024-09-30T00:00:00Z" => 1577
          }
        }
      })

    resp = %HTTPoison.Response{status_code: 200, body: body}

    HTTPoison
    |> Sanbase.Mock.prepare_mock(:post, fn _url, body, _headers, _options ->
      search_texts =
        body
        |> Jason.decode!()
        |> Map.get("search_texts")

      # Assert that the words are **not** lowercased before they are sent
      assert search_texts == "eth OR nft,BTC"

      {:ok, resp}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        wordsSocialVolume(
          selector: { words: ["eth OR nft", "BTC"] }
          from: "2024-09-28T00:00:00Z"
          to: "2024-09-30T00:00:00Z"
          interval: "1d"
          treatWordAsLuceneQuery: true
        ){
          word
          timeseriesData{
            datetime
            mentionsCount
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
                 "wordsSocialVolume" => [
                   %{
                     "timeseriesData" => [
                       %{"datetime" => "2024-09-28T00:00:00Z", "mentionsCount" => 373},
                       %{"datetime" => "2024-09-29T00:00:00Z", "mentionsCount" => 487},
                       %{"datetime" => "2024-09-30T00:00:00Z", "mentionsCount" => 323}
                     ],
                     "word" => "BTC"
                   },
                   %{
                     "timeseriesData" => [
                       %{"datetime" => "2024-09-28T00:00:00Z", "mentionsCount" => 1681},
                       %{"datetime" => "2024-09-29T00:00:00Z", "mentionsCount" => 3246},
                       %{"datetime" => "2024-09-30T00:00:00Z", "mentionsCount" => 1577}
                     ],
                     "word" => "eth OR nft"
                   }
                 ]
               }
             }
    end)
  end
end

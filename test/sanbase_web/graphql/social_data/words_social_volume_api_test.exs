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
      %{
        "data" => %{
          URI.encode_www_form("btc") => %{
            "2024-09-28T00:00:00Z" => 373,
            "2024-09-29T00:00:00Z" => 487,
            "2024-09-30T00:00:00Z" => 323
          },
          URI.encode_www_form("eth or nft") => %{
            "2024-09-28T00:00:00Z" => 1681,
            "2024-09-29T00:00:00Z" => 3246,
            "2024-09-30T00:00:00Z" => 1577
          }
        }
      }
      |> Jason.encode!()

    resp = %HTTPoison.Response{status_code: 200, body: body}

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn _url, _headers, options ->
      search_texts =
        Map.new(options[:params])
        |> Map.get("search_texts")

      # Assert that the words are lowercased and www form encoded
      assert search_texts ==
               URI.encode_www_form("eth or nft") <> "," <> URI.encode_www_form("btc")

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
      %{
        "data" => %{
          URI.encode_www_form("BTC") => %{
            "2024-09-28T00:00:00Z" => 373,
            "2024-09-29T00:00:00Z" => 487,
            "2024-09-30T00:00:00Z" => 323
          },
          URI.encode_www_form("eth OR nft") => %{
            "2024-09-28T00:00:00Z" => 1681,
            "2024-09-29T00:00:00Z" => 3246,
            "2024-09-30T00:00:00Z" => 1577
          }
        }
      }
      |> Jason.encode!()

    resp = %HTTPoison.Response{status_code: 200, body: body}

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn _url, _headers, options ->
      search_texts =
        Map.new(options[:params])
        |> Map.get("search_texts")

      # Assert that the words are **not** lowercased before they are sent
      assert search_texts ==
               URI.encode_www_form("eth OR nft") <> "," <> URI.encode_www_form("BTC")

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

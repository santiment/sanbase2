defmodule Sanbase.SocialDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mockery
  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  test "successfully fetch social data", %{conn: conn} do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"timestamp\": 1541808000, \"top_words\": {\"bat\": 367.77770422285084, \"pele\": 167.74716011726295, \"people\": 137.61557511242117, \"arn\": 137.14962816454351, \"chimeracryptoinsider\": 118.17637249353709}}, {\"timestamp\": 1541721600, \"top_words\": {\"bat\": 1740.2647984845628, \"xlm\": 837.0034350090417, \"coinbase\": 792.9209638684719, \"mth\": 721.8164660673655, \"mana\": 208.48182966076172}}, {\"timestamp\": 1541980800, \"top_words\": {\"xlm\": 769.8008634834883, \"bch\": 522.9358622900285, \"fork\": 340.17719444024317, \"mda\": 213.57227498303558, \"abc\": 177.6092706156777}}, {\"timestamp\": 1541894400, \"top_words\": {\"mana\": 475.8978759407794, \"mth\": 411.73069246798326, \"fork\": 321.11991967479867, \"bch\": 185.35627662699594, \"imgur\": 181.45123778369867}}]",
         status_code: 200
       }}
    )

    query = """
    {
      trendingWords(
        source: TELEGRAM,
        size: 5,
        hour: 8,
        from: "2018-11-05T00:00:00Z",
        to: "2018-11-12T00:00:00Z"){
          datetime
          topWords{
            word
            score
          }
        }
      }
    """

    # As the HTTP call is mocked these arguemnts do no have much effect, though you should try to put the real ones that are used
    result =
      conn
      |> post("/graphql", query_skeleton(query, "trendingWords"))
      |> json_response(200)

    assert result == %{
             "data" => %{
               "trendingWords" => [
                 %{
                   "datetime" => "2018-11-10T00:00:00Z",
                   "topWords" => [
                     %{"score" => 137.14962816454351, "word" => "arn"},
                     %{"score" => 367.77770422285084, "word" => "bat"},
                     %{
                       "score" => 118.17637249353709,
                       "word" => "chimeracryptoinsider"
                     },
                     %{"score" => 167.74716011726295, "word" => "pele"},
                     %{"score" => 137.61557511242117, "word" => "people"}
                   ]
                 },
                 %{
                   "datetime" => "2018-11-09T00:00:00Z",
                   "topWords" => [
                     %{"score" => 1740.2647984845628, "word" => "bat"},
                     %{"score" => 792.9209638684719, "word" => "coinbase"},
                     %{"score" => 208.48182966076172, "word" => "mana"},
                     %{"score" => 721.8164660673655, "word" => "mth"},
                     %{"score" => 837.0034350090417, "word" => "xlm"}
                   ]
                 },
                 %{
                   "datetime" => "2018-11-12T00:00:00Z",
                   "topWords" => [
                     %{"score" => 177.6092706156777, "word" => "abc"},
                     %{"score" => 522.9358622900285, "word" => "bch"},
                     %{"score" => 340.17719444024317, "word" => "fork"},
                     %{"score" => 213.57227498303558, "word" => "mda"},
                     %{"score" => 769.8008634834883, "word" => "xlm"}
                   ]
                 },
                 %{
                   "datetime" => "2018-11-11T00:00:00Z",
                   "topWords" => [
                     %{"score" => 185.35627662699594, "word" => "bch"},
                     %{"score" => 321.11991967479867, "word" => "fork"},
                     %{"score" => 181.45123778369867, "word" => "imgur"},
                     %{"score" => 475.8978759407794, "word" => "mana"},
                     %{"score" => 411.73069246798326, "word" => "mth"}
                   ]
                 }
               ]
             }
           }
  end

  test "error fetching social data", %{conn: conn} do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "Internal Server Error",
         status_code: 500
       }}
    )

    query = """
    {
      trendingWords(
        source: TELEGRAM,
        size: 5,
        hour: 8,
        from: "2018-11-05T00:00:00Z",
        to: "2018-11-12T00:00:00Z"){
          datetime
          topWords{
            word
            score
          }
        }
      }
    """

    result_fn = fn ->
      result =
        conn
        |> post("/graphql", query_skeleton(query, "trendingWords"))
        |> json_response(200)

      error = result["errors"] |> List.first()
      assert error["message"] =~ "Error executing query. See logs for details."
    end

    assert capture_log(result_fn) =~
             "Error status 500 fetching trending words for source: telegram: Internal Server Error"
  end

  test "successfully fetch word context", %{conn: conn} do
    body =
      %{
        "christ" => %{"size" => 0.7688603531300161},
        "christmas" => %{"size" => 0.7592295345104334},
        "mas" => %{"size" => 1.0}
      }
      |> Jason.encode!()

    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: body,
         status_code: 200
       }}
    )

    query = """
    {
      wordContext(
        word: "merry", 
        source: TELEGRAM,
        size: 3,
        from: "2018-12-22T00:00:00Z",
        to:"2018-12-27T00:00:00Z"
      ) {
        word
        size
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "wordContext"))
      |> json_response(200)

    assert result == %{
             "data" => %{
               "wordContext" => [
                 %{"size" => 1.0, "word" => "mas"},
                 %{"size" => 0.7688603531300161, "word" => "christ"},
                 %{"size" => 0.7592295345104334, "word" => "christmas"}
               ]
             }
           }
  end
end

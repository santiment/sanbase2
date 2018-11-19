defmodule Sanbase.SocialDataTest do
  use Sanbase.DataCase, async: true

  import Mockery
  import ExUnit.CaptureLog

  alias Sanbase.SocialData

  test "successfully fetch social data", _context do
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

    # As the HTTP call is mocked these arguemnts do no have much effect, though you should try to put the real ones that are used
    result =
      SocialData.trending_words(
        :telegram,
        5,
        8,
        DateTime.from_naive!(~N[2018-11-05 00:00:00], "Etc/UTC"),
        DateTime.from_naive!(~N[2018-11-12 00:00:00], "Etc/UTC")
      )

    assert result ==
             {:ok,
              [
                %{
                  datetime: DateTime.from_naive!(~N[2018-11-10 00:00:00], "Etc/UTC"),
                  top_words: [
                    %{score: 137.14962816454351, word: "arn"},
                    %{score: 367.77770422285084, word: "bat"},
                    %{score: 118.17637249353709, word: "chimeracryptoinsider"},
                    %{score: 167.74716011726295, word: "pele"},
                    %{score: 137.61557511242117, word: "people"}
                  ]
                },
                %{
                  datetime: DateTime.from_naive!(~N[2018-11-09 00:00:00], "Etc/UTC"),
                  top_words: [
                    %{score: 1740.2647984845628, word: "bat"},
                    %{score: 792.9209638684719, word: "coinbase"},
                    %{score: 208.48182966076172, word: "mana"},
                    %{score: 721.8164660673655, word: "mth"},
                    %{score: 837.0034350090417, word: "xlm"}
                  ]
                },
                %{
                  datetime: DateTime.from_naive!(~N[2018-11-12 00:00:00], "Etc/UTC"),
                  top_words: [
                    %{score: 177.6092706156777, word: "abc"},
                    %{score: 522.9358622900285, word: "bch"},
                    %{score: 340.17719444024317, word: "fork"},
                    %{score: 213.57227498303558, word: "mda"},
                    %{score: 769.8008634834883, word: "xlm"}
                  ]
                },
                %{
                  datetime: DateTime.from_naive!(~N[2018-11-11 00:00:00], "Etc/UTC"),
                  top_words: [
                    %{score: 185.35627662699594, word: "bch"},
                    %{score: 321.11991967479867, word: "fork"},
                    %{score: 181.45123778369867, word: "imgur"},
                    %{score: 475.8978759407794, word: "mana"},
                    %{score: 411.73069246798326, word: "mth"}
                  ]
                }
              ]}
  end

  test "error fetching social data", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "Internal Server Error",
         status_code: 500
       }}
    )

    result_fn = fn ->
      result =
        SocialData.trending_words(
          :telegram,
          5,
          8,
          DateTime.from_naive!(~N[2018-11-05 00:00:00], "Etc/UTC"),
          DateTime.from_naive!(~N[2018-11-12 00:00:00], "Etc/UTC")
        )

      {:error, error_message} = result

      assert error_message =~ "Error executing query. See logs for details"
    end

    assert capture_log(result_fn) =~
             "Error status 500 fetching trending words for source: telegram: Internal Server Error"
  end
end

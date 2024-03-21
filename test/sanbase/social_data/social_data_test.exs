defmodule Sanbase.SocialDataTest do
  use Sanbase.DataCase, async: false

  import Mockery
  import ExUnit.CaptureLog

  alias Sanbase.SocialData

  test "successfully fetch word context" do
    body =
      %{
        "christ" => %{"score" => 0.7688603531300161},
        "christmas" => %{"score" => 0.7592295345104334},
        "mas" => %{"score" => 1.0}
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

    # As the HTTP call is mocked these arguemnts do no have much effect,
    # though you should try to put the real ones that are used
    result =
      SocialData.word_context(
        "merry",
        :telegram,
        3,
        DateTime.from_naive!(~N[2018-12-22 00:00:00], "Etc/UTC"),
        DateTime.from_naive!(~N[2018-12-27 00:00:00], "Etc/UTC")
      )

    assert result ==
             {:ok,
              [
                %{score: 1.0, word: "mas"},
                %{score: 0.7688603531300161, word: "christ"},
                %{score: 0.7592295345104334, word: "christmas"}
              ]}
  end

  test "successfully fetch word trend score" do
    body =
      [
        %{
          "hour" => 8.0,
          "score" => 3725.6617392595313,
          "source" => "telegram",
          "timestamp" => DateTime.to_unix(~U[2019-01-10 00:00:00Z])
        }
      ]
      |> Jason.encode!()

    mock(
      HTTPoison,
      :get,
      {:ok, %HTTPoison.Response{body: body, status_code: 200}}
    )

    # As the HTTP call is mocked these arguemnts do no have much effect,
    # though you should try to put the real ones that are used
    assert {:ok, result} =
             SocialData.word_trend_score(
               "trx",
               :telegram,
               ~U[2019-01-10 00:00:00Z],
               ~U[2019-01-11 00:00:00Z]
             )

    # Avoid error with truncated microseconds
    result =
      Enum.map(result, fn map -> Map.update!(map, :datetime, &DateTime.truncate(&1, :second)) end)

    assert result ==
             [
               %{
                 score: 3725.6617392595313,
                 source: :telegram,
                 datetime: ~U[2019-01-10 08:00:00Z]
               }
             ]
  end
end

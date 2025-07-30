defmodule Sanbase.SocialDataTest do
  use Sanbase.DataCase, async: false

  import Mockery

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
end

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

  test "successfully fetch top social gainers losers", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "[{
             \"timestamp\": 1552654800, \"range\": \"15d\", \"projects\":
            [
              {\"project\": \"qtum\", \"change\": 137.13186813186815, \"status\": \"gainer\"},
              {\"project\": \"abbc-coin\", \"change\": -1.0, \"status\": \"loser\"}
            ]
           }]",
         status_code: 200
       }}
    )

    args = %{
      status: :all,
      from: DateTime.from_naive!(~N[2019-03-15 12:57:28], "Etc/UTC"),
      to: DateTime.from_naive!(~N[2019-03-15 13:57:28], "Etc/UTC"),
      time_window: "15d",
      size: 1
    }

    # As the HTTP call is mocked these arguments do no have much effect,
    # though you should try to put the real ones that are used
    result = SocialData.top_social_gainers_losers(args)

    assert result ==
             {:ok,
              [
                %{
                  datetime: DateTime.from_naive!(~N[2019-03-15 13:00:00], "Etc/UTC"),
                  projects: [
                    %{change: 137.13186813186815, slug: "qtum", status: :gainer},
                    %{change: -1.0, slug: "abbc-coin", status: :loser}
                  ]
                }
              ]}
  end

  test "error fetching top social gainers losers" do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "Internal Server Error",
         status_code: 500
       }}
    )

    args = %{
      status: :all,
      from: DateTime.from_naive!(~N[2019-03-15 12:57:28], "Etc/UTC"),
      to: DateTime.from_naive!(~N[2019-03-15 13:57:28], "Etc/UTC"),
      time_window: "15d",
      size: 1
    }

    result_fn = fn ->
      {:error, error_message} = SocialData.top_social_gainers_losers(args)

      assert error_message =~ "Error executing query. See logs for details"
    end

    assert capture_log(result_fn) =~
             "Error status 500 fetching top social gainers losers for status: all: Internal Server Error"
  end

  test "successfully fetch social gainers losers status for slug" do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"timestamp\": 1552662000, \"status\": \"gainer\", \"change\": 12.709016393442624}]",
         status_code: 200
       }}
    )

    args = %{
      slug: "qtum",
      from: DateTime.from_naive!(~N[2019-03-15 12:57:28], "Etc/UTC"),
      to: DateTime.from_naive!(~N[2019-03-15 13:57:28], "Etc/UTC"),
      time_window: "15d"
    }

    # As the HTTP call is mocked these arguments do no have much effect,
    # though you should try to put the real ones that are used
    result = SocialData.social_gainers_losers_status(args)

    assert result ==
             {:ok,
              [
                %{
                  change: 12.709016393442624,
                  datetime: DateTime.from_naive!(~N[2019-03-15 15:00:00], "Etc/UTC"),
                  status: :gainer
                }
              ]}
  end

  test "error fetching social gainers losers status" do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "Internal Server Error",
         status_code: 500
       }}
    )

    args = %{
      slug: "qtum",
      from: DateTime.from_naive!(~N[2019-03-15 12:57:28], "Etc/UTC"),
      to: DateTime.from_naive!(~N[2019-03-15 13:57:28], "Etc/UTC"),
      time_window: "15d"
    }

    result_fn = fn ->
      {:error, error_message} = SocialData.social_gainers_losers_status(args)

      assert error_message =~ "Error executing query. See logs for details"
    end

    assert capture_log(result_fn) =~
             "Error status 500 fetching social gainers losers status for slug: qtum: Internal Server Error"
  end

  test "top_social_gainers_losers: error with invalid time_window" do
    args = %{
      status: :all,
      from: DateTime.from_naive!(~N[2019-03-15 12:57:28], "Etc/UTC"),
      to: DateTime.from_naive!(~N[2019-03-15 13:57:28], "Etc/UTC"),
      time_window: "invalid",
      size: 1
    }

    result_fn = fn ->
      {:error, error_message} = SocialData.top_social_gainers_losers(args)

      assert error_message =~
               "Invalid string format for time_window. Valid values can be - for ex: `2d`, `5d`, `1w`"
    end

    capture_log(result_fn)
  end

  test "top_social_gainers_losers: error with out of bounds time_window" do
    args = %{
      status: :all,
      from: DateTime.from_naive!(~N[2019-03-15 12:57:28], "Etc/UTC"),
      to: DateTime.from_naive!(~N[2019-03-15 13:57:28], "Etc/UTC"),
      time_window: "1d",
      size: 1
    }

    result_fn = fn ->
      {:error, error_message} = SocialData.top_social_gainers_losers(args)

      assert error_message =~
               "Invalid `time_window` argument. time_window should be between 2 and 30 days - for ex: `2d`, `5d`, `1w`"
    end

    capture_log(result_fn)
  end
end

defmodule Sanbase.SocialDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Mockery
  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.SocialData
  alias Sanbase.DateTimeUtils

  @error_response "Error executing query. See logs for details."

  test "successfully fetch trending words", %{conn: conn} do
    success_response = [
      %{
        datetime: DateTimeUtils.from_iso8601!("2018-11-10T00:00:00Z"),
        top_words: [
          %{score: 167.74716011726295, word: "pele"},
          %{score: 137.61557511242117, word: "people"}
        ]
      }
    ]

    with_mock SocialData, trending_words: fn _, _, _, _, _ -> {:ok, success_response} end do
      args = %{
        source: "TELEGRAM",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z",
        size: 1,
        hour: 8
      }

      query = trending_words_query(args)
      result = execute_and_parse_success_response(conn, query, "trendingWords")

      assert result == %{
               "data" => %{
                 "trendingWords" => [
                   %{
                     "datetime" => "2018-11-10T00:00:00Z",
                     "topWords" => [
                       %{"score" => 167.74716011726295, "word" => "pele"},
                       %{"score" => 137.61557511242117, "word" => "people"}
                     ]
                   }
                 ]
               }
             }
    end
  end

  test "fetch trending words - proper error is returned", %{conn: conn} do
    with_mock SocialData, trending_words: fn _, _, _, _, _ -> {:error, @error_response} end do
      args = %{
        source: "TELEGRAM",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z",
        size: 1,
        hour: 8
      }

      query = trending_words_query(args)
      error = execute_and_parse_error_response(conn, query, "trendingWords")
      assert error =~ @error_response
    end
  end

  test "successfully fetch word context", %{conn: conn} do
    success_response = [
      %{score: 1.0, word: "mas"},
      %{score: 0.7688603531300161, word: "christ"},
      %{score: 0.7592295345104334, word: "christmas"}
    ]

    with_mock SocialData, word_context: fn _, _, _, _, _ -> {:ok, success_response} end do
      args = %{
        word: "merry",
        source: "TELEGRAM",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z",
        size: 1
      }

      query = word_context_query(args)
      result = execute_and_parse_success_response(conn, query, "wordContext")

      assert result == %{
               "data" => %{
                 "wordContext" => [
                   %{"score" => 1.0, "word" => "mas"},
                   %{"score" => 0.7688603531300161, "word" => "christ"},
                   %{"score" => 0.7592295345104334, "word" => "christmas"}
                 ]
               }
             }
    end
  end

  test "fetch word context - proper error is returned", %{conn: conn} do
    with_mock SocialData, word_context: fn _, _, _, _, _ -> {:error, @error_response} end do
      args = %{
        word: "merry",
        source: "TELEGRAM",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z",
        size: 1
      }

      query = word_context_query(args)
      error = execute_and_parse_error_response(conn, query, "wordContext")
      assert error =~ @error_response
    end
  end

  test "successfully fetch word trend score", %{conn: conn} do
    success_response = [
      %{
        score: 3725.6617392595313,
        source: :telegram,
        datetime: DateTimeUtils.from_iso8601!("2019-01-10T08:00:00Z")
      }
    ]

    with_mock SocialData, word_trend_score: fn _, _, _, _ -> {:ok, success_response} end do
      args = %{
        word: "qtum",
        source: "TELEGRAM",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z"
      }

      query = word_trend_score_query(args)
      result = execute_and_parse_success_response(conn, query, "wordTrendScore")

      assert result == %{
               "data" => %{
                 "wordTrendScore" => [
                   %{
                     "score" => 3725.6617392595313,
                     "source" => "TELEGRAM",
                     "datetime" => "2019-01-10T08:00:00Z"
                   }
                 ]
               }
             }
    end
  end

  test "fetching word trend score - proper error message is returned", %{conn: conn} do
    error_response =
      "Error status 500 fetching word trend score for word merry: Internal Server Error"

    with_mock SocialData, word_trend_score: fn _, _, _, _ -> {:error, error_response} end do
      args = %{
        word: "merry",
        source: "TELEGRAM",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z"
      }

      query = word_trend_score_query(args)
      error = execute_and_parse_error_response(conn, query, "wordTrendScore")
      assert error == error_response
    end
  end

  test "successfully fetch top social gainers losers", %{conn: conn} do
    success_response = [
      %{
        datetime: DateTimeUtils.from_iso8601!("2019-03-15T13:00:00Z"),
        projects: [
          %{
            change: 137.13186813186815,
            project: "qtum",
            status: :gainer
          },
          %{
            change: -1.0,
            project: "abbc-coin",
            status: :loser
          }
        ]
      }
    ]

    with_mock SocialData, top_social_gainers_losers: fn _ -> {:ok, success_response} end do
      args = %{
        status: "ALL",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z",
        range: "15d",
        size: 1
      }

      query = top_social_gainers_losers_query(args)
      result = execute_and_parse_success_response(conn, query, "topSocialGainersLosers")

      func_args = %{
        args
        | status: args.status |> String.downcase() |> String.to_existing_atom(),
          from: DateTimeUtils.from_iso8601!(args.from),
          to: DateTimeUtils.from_iso8601!(args.to)
      }

      assert_called(SocialData.top_social_gainers_losers(func_args))

      assert result == %{
               "data" => %{
                 "topSocialGainersLosers" => [
                   %{
                     "datetime" => "2019-03-15T13:00:00Z",
                     "projects" => [
                       %{
                         "change" => 137.13186813186815,
                         "project" => "qtum",
                         "status" => "GAINER"
                       },
                       %{
                         "change" => -1.0,
                         "project" => "abbc-coin",
                         "status" => "LOSER"
                       }
                     ]
                   }
                 ]
               }
             }
    end
  end

  test "fetch top social gainers losers - proper error is returned", %{conn: conn} do
    with_mock SocialData, top_social_gainers_losers: fn _ -> {:error, @error_response} end do
      args = %{
        status: "ALL",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z",
        range: "15d",
        size: 1
      }

      query = top_social_gainers_losers_query(args)
      error = execute_and_parse_error_response(conn, query, "topSocialGainersLosers")
      assert error =~ @error_response
    end
  end

  test "successfully fetch social gainers losers status for slug", %{conn: conn} do
    success_response = [
      %{
        change: 12.709016393442624,
        datetime: DateTimeUtils.from_iso8601!("2019-03-15T15:00:00Z"),
        status: :gainer
      }
    ]

    with_mock SocialData, social_gainers_losers_status: fn _ -> {:ok, success_response} end do
      args = %{
        slug: "qtum",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z",
        range: "15d"
      }

      query = social_gainers_losers_status_query(args)
      result = execute_and_parse_success_response(conn, query, "socialGainersLosersStatus")

      func_args = %{
        args
        | from: DateTimeUtils.from_iso8601!(args.from),
          to: DateTimeUtils.from_iso8601!(args.to)
      }

      assert_called(SocialData.social_gainers_losers_status(func_args))

      assert result == %{
               "data" => %{
                 "socialGainersLosersStatus" => [
                   %{
                     "change" => 12.709016393442624,
                     "datetime" => "2019-03-15T15:00:00Z",
                     "status" => "GAINER"
                   }
                 ]
               }
             }
    end
  end

  test "fetching social gainers losers status - proper error message is returned", %{conn: conn} do
    error_response =
      "Error status 500 fetching social gainers losers status for slug: qtum: Internal Server Error"

    with_mock SocialData, social_gainers_losers_status: fn _ -> {:error, @error_response} end do
      args = %{
        slug: "qtum",
        from: "2018-01-09T00:00:00Z",
        to: "2018-01-10T00:00:00Z",
        range: "15d"
      }

      query = social_gainers_losers_status_query(args)
      error = execute_and_parse_error_response(conn, query, "topSocialGainersLosers")
      assert error =~ @error_response
    end
  end

  # private functions

  defp trending_words_query(args) do
    """
    {
      trendingWords(
        source: #{args.source},
        from: "#{args.from}",
        to: "#{args.to}",
        size: 5,
        hour: 8
        ){
          datetime
          topWords{
            word
            score
          }
        }
      }
    """
  end

  defp word_context_query(args) do
    """
    {
      wordContext(
        word: "#{args.word}", 
        source: #{args.source},
        from: "#{args.from}",
        to: "#{args.to}",
        size: #{args.size}
      ) {
        word
        score
      }
    }
    """
  end

  defp word_trend_score_query(args) do
    """
    {
      wordTrendScore(
        word: "#{args.word}", 
        source: #{args.source},
        from: "#{args.from}",
        to: "#{args.to}"
      ) {
        datetime,
        score,
        source
      }
    }
    """
  end

  defp top_social_gainers_losers_query(args) do
    """
    {
      topSocialGainersLosers(
        status: #{args.status}, 
        from: "#{args.from}",
        to: "#{args.to}",
        range: "#{args.range}",
        size: #{args.size}
      ) {
        datetime,
        projects {
          project,
          change,
          status
        }
      }
    }
    """
  end

  defp social_gainers_losers_status_query(args) do
    """
    {
      socialGainersLosersStatus(
        slug: "#{args.slug}",
        from: "#{args.from}",
        to: "#{args.to}",
        range: "#{args.range}"
      ) {
        datetime,
        change,
        status
      }
    }
    """
  end

  defp execute_and_parse_success_response(conn, query, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
  end

  defp execute_and_parse_error_response(conn, query, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
    |> Map.get("message")
  end
end

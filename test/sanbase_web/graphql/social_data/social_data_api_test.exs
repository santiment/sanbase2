defmodule SanbaseWeb.Graphql.SocialDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Mockery

  alias Sanbase.SocialData
  alias Sanbase.DateTimeUtils

  @error_response "Error executing query. See logs for details."

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  describe "trending words" do
    test "successfully fetch trending words", context do
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
        result = execute_and_parse_success_response(context.conn, query, "trendingWords")

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

    test "fetch trending words - proper error is returned", context do
      with_mock SocialData, trending_words: fn _, _, _, _, _ -> {:error, @error_response} end do
        args = %{
          source: "TELEGRAM",
          from: "2018-01-09T00:00:00Z",
          to: "2018-01-10T00:00:00Z",
          size: 1,
          hour: 8
        }

        query = trending_words_query(args)
        error = execute_and_parse_error_response(context.conn, query, "trendingWords")
        assert error =~ @error_response
      end
    end
  end

  describe "word context" do
    test "successfully fetch word context", context do
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
        result = execute_and_parse_success_response(context.conn, query, "wordContext")

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

    test "fetch word context - proper error is returned", context do
      with_mock SocialData, word_context: fn _, _, _, _, _ -> {:error, @error_response} end do
        args = %{
          word: "merry",
          source: "TELEGRAM",
          from: "2018-01-09T00:00:00Z",
          to: "2018-01-10T00:00:00Z",
          size: 1
        }

        query = word_context_query(args)
        error = execute_and_parse_error_response(context.conn, query, "wordContext")
        assert error =~ @error_response
      end
    end
  end

  describe "trend score" do
    test "successfully fetch word trend score", context do
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
        result = execute_and_parse_success_response(context.conn, query, "wordTrendScore")

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

    test "fetching word trend score - proper error message is returned", context do
      error_response =
        "Error status 500 fetching word trend score for word merry: Internal Server Error"

      with_mock SocialData, word_trend_score: fn _, _, _, _ -> {:error, error_response} end do
        args = %{
          word: "merry",
          source: "TELEGRAM",
          from: "#{Timex.shift(Timex.now(), days: -20)}",
          to: "#{Timex.now()}"
        }

        query = word_trend_score_query(args)
        error = execute_and_parse_error_response(context.conn, query, "wordTrendScore")
        assert error == error_response
      end
    end
  end

  describe "social gainers/losers" do
    test "successfully fetch top social gainers losers", context do
      p1 = insert(:random_project)
      p2 = insert(:random_project)

      success_response = [
        %{
          datetime: DateTimeUtils.from_iso8601!("2019-03-15T13:00:00Z"),
          projects: [
            %{
              change: 137.13186813186815,
              slug: p1.slug,
              status: :gainer
            },
            %{
              change: -1.0,
              slug: p2.slug,
              status: :loser
            }
          ]
        }
      ]

      with_mock SocialData, top_social_gainers_losers: fn _ -> {:ok, success_response} end do
        args = %{
          status: "ALL",
          from: Timex.now() |> Timex.shift(days: -10) |> DateTime.to_iso8601(),
          to: Timex.now() |> Timex.shift(days: -2) |> DateTime.to_iso8601(),
          time_window: "15d",
          size: 1
        }

        query = top_social_gainers_losers_query(args)

        result =
          execute_and_parse_success_response(context.conn, query, "topSocialGainersLosers")
          |> get_in(["data", "topSocialGainersLosers"])

        assert result == [
                 %{
                   "datetime" => "2019-03-15T13:00:00Z",
                   "projects" => [
                     %{
                       "project" => %{"slug" => p1.slug},
                       "slug" => p1.slug,
                       "change" => 137.13186813186815,
                       "status" => "GAINER"
                     },
                     %{
                       "project" => %{"slug" => p2.slug},
                       "slug" => p2.slug,
                       "change" => -1.0,
                       "status" => "LOSER"
                     }
                   ]
                 }
               ]
      end
    end

    test "fetch top social gainers losers - proper error is returned", context do
      with_mock SocialData, top_social_gainers_losers: fn _ -> {:error, @error_response} end do
        args = %{
          status: "ALL",
          from: "2018-01-09T00:00:00Z",
          to: "2018-01-10T00:00:00Z",
          time_window: "15d",
          size: 1
        }

        query = top_social_gainers_losers_query(args)

        error = execute_and_parse_error_response(context.conn, query, "topSocialGainersLosers")

        assert error =~ @error_response
      end
    end

    test "successfully fetch social gainers losers status for slug", context do
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
          from: Timex.now() |> Timex.shift(days: -10) |> DateTime.to_iso8601(),
          to: Timex.now() |> Timex.shift(days: -2) |> DateTime.to_iso8601(),
          time_window: "15d"
        }

        query = social_gainers_losers_status_query(args)

        result =
          execute_and_parse_success_response(
            context.conn,
            query,
            "socialGainersLosersStatus"
          )

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

    test "fetching social gainers losers status - proper error message is returned", context do
      with_mock SocialData, social_gainers_losers_status: fn _ -> {:error, @error_response} end do
        args = %{
          slug: "qtum",
          from: "2018-01-09T00:00:00Z",
          to: "2018-01-10T00:00:00Z",
          time_window: "15d"
        }

        query = social_gainers_losers_status_query(args)

        error = execute_and_parse_error_response(context.conn, query, "topSocialGainersLosers")

        assert error =~ @error_response
      end
    end
  end

  describe "news" do
    test "successfully fetch news", context do
      success_response = [
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!("2018-04-16T10:00:00Z"),
          description: "test description",
          media_url: "http://alabala",
          source_name: "ForexTV.com",
          title: "test title",
          url: "http://example.com"
        }
      ]

      with_mock SocialData, google_news: fn _, _, _, _ -> {:ok, success_response} end do
        args = %{
          tag: "qtum",
          from: "2018-01-09T00:00:00Z",
          to: "2018-01-10T00:00:00Z",
          size: 10
        }

        query = news_query(args)
        result = execute_and_parse_success_response(context.conn, query, "news")

        assert result == %{
                 "data" => %{
                   "news" => [
                     %{
                       "datetime" => "2018-04-16T10:00:00Z",
                       "description" => "test description",
                       "mediaUrl" => "http://alabala",
                       "sourceName" => "ForexTV.com",
                       "title" => "test title",
                       "url" => "http://example.com"
                     }
                   ]
                 }
               }
      end
    end

    test "fetching news error", context do
      with_mock SocialData, google_news: fn _, _, _, _ -> {:error, @error_response} end do
        args = %{
          tag: "qtum",
          from: "2018-01-09T00:00:00Z",
          to: "2018-01-10T00:00:00Z",
          size: 10
        }

        query = news_query(args)

        error = execute_and_parse_error_response(context.conn, query, "news")

        assert error =~ @error_response
      end
    end
  end

  describe "#social_active_users" do
    test "when response is success", context do
      success_response =
        %{
          "data" => %{
            "2020-08-23T00:00:00Z" => 11794,
            "2020-08-24T00:00:00Z" => 18748,
            "2020-08-25T00:00:00Z" => 20154,
            "2020-08-26T00:00:00Z" => 23537,
            "2020-08-27T00:00:00Z" => 24085,
            "2020-08-28T00:00:00Z" => 18121,
            "2020-08-29T00:00:00Z" => 14383,
            "2020-08-30T00:00:00Z" => 13149,
            "2020-08-31T00:00:00Z" => 15294,
            "2020-09-01T00:00:00Z" => 22666,
            "2020-09-02T00:00:00Z" => 11981
          }
        }
        |> Jason.encode!()

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: success_response, status_code: 200}})

      args = %{
        source: "TELEGRAM",
        from: "2020-08-23T00:00:00Z",
        to: "2020-09-02T00:00:00Z"
      }

      query = social_active_users_query(args)
      res = execute_and_parse_success_response(context.conn, query, "socialActiveUsers")

      assert res == %{
               "data" => %{
                 "socialActiveUsers" => [
                   %{"datetime" => "2020-08-23T00:00:00Z", "value" => 11794},
                   %{"datetime" => "2020-08-24T00:00:00Z", "value" => 18748},
                   %{"datetime" => "2020-08-25T00:00:00Z", "value" => 20154},
                   %{"datetime" => "2020-08-26T00:00:00Z", "value" => 23537},
                   %{"datetime" => "2020-08-27T00:00:00Z", "value" => 24085},
                   %{"datetime" => "2020-08-28T00:00:00Z", "value" => 18121},
                   %{"datetime" => "2020-08-29T00:00:00Z", "value" => 14383},
                   %{"datetime" => "2020-08-30T00:00:00Z", "value" => 13149},
                   %{"datetime" => "2020-08-31T00:00:00Z", "value" => 15294},
                   %{"datetime" => "2020-09-01T00:00:00Z", "value" => 22666},
                   %{"datetime" => "2020-09-02T00:00:00Z", "value" => 11981}
                 ]
               }
             }
    end

    test "when empty response", context do
      resp = %{"data" => %{}} |> Jason.encode!()
      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: resp, status_code: 200}})

      args = %{
        source: "TELEGRAM",
        from: "2020-08-23T00:00:00Z",
        to: "2020-09-02T00:00:00Z"
      }

      query = social_active_users_query(args)
      res = execute_and_parse_success_response(context.conn, query, "socialActiveUsers")
      assert res == %{"data" => %{"socialActiveUsers" => []}}
    end
  end

  defp social_active_users_query(args) do
    """
    {
      socialActiveUsers(
        source: #{args.source},
        from: "#{args.from}",
        to: "#{args.to}"
        ){
          datetime
          value
        }
      }
    """
  end

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
        status: #{args.status}
        from: "#{args.from}"
        to: "#{args.to}"
        timeWindow: "#{args.time_window}"
        size: #{args.size}
      ) {
        datetime
        projects {
          project{ slug }
          slug
          change
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
        slug: "#{args.slug}"
        from: "#{args.from}"
        to: "#{args.to}"
        timeWindow: "#{args.time_window}"
      ) {
        datetime,
        change
        status
      }
    }
    """
  end

  defp news_query(args) do
    """
    {
      news(
        tag: "#{args.tag}"
        from: "#{args.from}",
        to: "#{args.to}",
        size: #{args.size}
      ) {
        datetime,
       title,
        description,
        url,
        mediaUrl,
        sourceName
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

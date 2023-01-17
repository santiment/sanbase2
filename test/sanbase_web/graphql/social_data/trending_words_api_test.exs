defmodule SanbaseWeb.Graphql.TrendingWordsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.SocialData

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      dt1: ~U[2019-01-01 00:00:00Z],
      dt2: ~U[2019-01-02 00:00:00Z],
      dt3: ~U[2019-01-03 00:00:00Z]
    ]
  end

  describe "get trending words api" do
    test "success", context do
      %{dt1: dt1, dt2: dt2, dt3: dt3} = context

      success_response = %{
        dt1 => [
          %{score: 1, word: "pele"},
          %{score: 2, word: "people"}
        ],
        dt2 => [
          %{score: 3, word: "btx"},
          %{score: 4, word: "eth"}
        ],
        dt3 => [
          %{score: 5, word: "omg"},
          %{score: 6, word: "wtf"}
        ]
      }

      with_mock SocialData.TrendingWords,
        get_trending_words: fn _, _, _, _, _ -> {:ok, success_response} end do
        args = %{from: dt1, to: dt3, interval: "1d", size: 2}

        query = trending_words_query(args)
        result = execute(context.conn, query)

        assert result == %{
                 "data" => %{
                   "getTrendingWords" => [
                     %{
                       "datetime" => DateTime.to_iso8601(dt1),
                       "topWords" => [
                         %{"score" => 2, "word" => "people"},
                         %{"score" => 1, "word" => "pele"}
                       ]
                     },
                     %{
                       "datetime" => DateTime.to_iso8601(dt2),
                       "topWords" => [
                         %{"score" => 4, "word" => "eth"},
                         %{"score" => 3, "word" => "btx"}
                       ]
                     },
                     %{
                       "datetime" => DateTime.to_iso8601(dt3),
                       "topWords" => [
                         %{"score" => 6, "word" => "wtf"},
                         %{"score" => 5, "word" => "omg"}
                       ]
                     }
                   ]
                 }
               }
      end
    end

    test "error", context do
      %{dt1: dt1, dt2: dt2} = context

      with_mock SocialData.TrendingWords,
        get_trending_words: fn _, _, _, _, _ -> {:error, "Something broke"} end do
        args = %{from: dt1, to: dt2, interval: "1h", size: 10}

        query = trending_words_query(args)

        error_msg =
          execute(context.conn, query)
          |> get_error_message()

        assert error_msg =~ "Something broke"
      end
    end
  end

  describe "get word trending history api" do
    test "success", context do
      %{dt1: dt1, dt2: dt2, dt3: dt3} = context

      success_response = [
        %{datetime: dt1, position: nil},
        %{datetime: dt2, position: 10},
        %{datetime: dt3, position: 1}
      ]

      with_mock SocialData.TrendingWords,
        get_word_trending_history: fn _, _, _, _, _ -> {:ok, success_response} end do
        args = %{word: "word", from: dt1, to: dt3, interval: "1d", size: 10}

        query = word_trending_history_query(args)
        result = execute(context.conn, query)

        assert result == %{
                 "data" => %{
                   "getWordTrendingHistory" => [
                     %{"datetime" => DateTime.to_iso8601(dt1), "position" => nil},
                     %{"datetime" => DateTime.to_iso8601(dt2), "position" => 10},
                     %{"datetime" => DateTime.to_iso8601(dt3), "position" => 1}
                   ]
                 }
               }
      end
    end

    test "error", context do
      %{dt1: dt1, dt2: dt2} = context

      with_mock SocialData.TrendingWords,
        get_word_trending_history: fn _, _, _, _, _ -> {:error, "Something went wrong"} end do
        args = %{word: "word", from: dt1, to: dt2, interval: "1d", size: 10}

        query = word_trending_history_query(args)

        error_msg =
          execute(context.conn, query)
          |> get_error_message()

        assert error_msg =~ "Something went wrong"
      end
    end
  end

  describe "get project trending history api" do
    test "success", context do
      %{dt1: dt1, dt2: dt2, dt3: dt3} = context
      project = insert(:random_project)

      success_response = [
        %{datetime: dt1, position: 5},
        %{datetime: dt2, position: nil},
        %{datetime: dt3, position: 10}
      ]

      with_mock SocialData.TrendingWords,
        get_project_trending_history: fn _, _, _, _, _ -> {:ok, success_response} end do
        args = %{
          slug: project.slug,
          from: dt1,
          to: dt3,
          interval: "1d",
          size: 10
        }

        query = project_trending_history_query(args)
        result = execute(context.conn, query)

        assert result == %{
                 "data" => %{
                   "getProjectTrendingHistory" => [
                     %{"datetime" => DateTime.to_iso8601(dt1), "position" => 5},
                     %{"datetime" => DateTime.to_iso8601(dt2), "position" => nil},
                     %{"datetime" => DateTime.to_iso8601(dt3), "position" => 10}
                   ]
                 }
               }
      end
    end

    test "error", context do
      %{dt1: dt1, dt2: dt2} = context

      with_mock SocialData.TrendingWords,
        get_word_trending_history: fn _, _, _, _, _ -> {:error, "Something went wrong"} end do
        args = %{word: "word", from: dt1, to: dt2, interval: "1d", size: 10}

        query = word_trending_history_query(args)

        error_msg =
          execute(context.conn, query)
          |> get_error_message()

        assert error_msg =~ "Something went wrong"
      end
    end
  end

  defp trending_words_query(args) do
    """
    {
      getTrendingWords(
        from: "#{args.from}"
        to: "#{args.to}"
        interval: "#{args.interval}"
        size: #{args.size},
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

  defp word_trending_history_query(args) do
    """
    {
    getWordTrendingHistory(
      word: "#{args.word}"
      from: "#{args.from}"
      to: "#{args.to}"
      interval: "#{args.interval}"
      size: #{args.size},
      ){
        datetime
        position
      }
    }
    """
  end

  defp project_trending_history_query(args) do
    """
    {
    getProjectTrendingHistory(
      slug: "#{args.slug}"
      from: "#{args.from}"
      to: "#{args.to}"
      interval: "#{args.interval}"
      size: #{args.size},
      ){
        datetime
        position
      }
    }
    """
  end

  defp execute(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_error_message(result) do
    result
    |> Map.get("errors")
    |> hd()
    |> Map.get("message")
  end
end

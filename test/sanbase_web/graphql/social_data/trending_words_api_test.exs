defmodule SanbaseWeb.Graphql.TrendingWordsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.SocialData

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    insert(:project, slug: "bitcoin", ticker: "BTC", name: "Bitcoin")
    insert(:project, slug: "ethereum", ticker: "ETH", name: "Ethereum")

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
      %{dt1: dt1, dt3: dt3} = context

      rows = [
        [
          DateTime.to_unix(dt1),
          "eth",
          "ETH_ethereum",
          72.4,
          [
            "{'word': 'btc', 'score': 0.85}",
            "{'word': 'halving', 'score': 1.0}"
          ],
          "The summary"
        ],
        [
          DateTime.to_unix(dt1),
          "btc",
          "BTC_bitcoin",
          74.5,
          [
            "{'word': 'eth', 'score': 0.63}",
            "{'word': 'bitcoin', 'score': 1.0}"
          ],
          "Another summary"
        ],
        [
          DateTime.to_unix(dt1),
          "word",
          nil,
          82.0,
          [
            "{'word': 'short', 'score': 0.82}",
            "{'word': 'tight', 'score': 1.0}"
          ],
          "Third summary"
        ]
      ]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        args = %{from: dt1, to: dt3, interval: "1d", size: 2}

        query = trending_words_query(args)
        result = execute(context.conn, query)

        assert result == %{
                 "data" => %{
                   "getTrendingWords" => [
                     %{
                       "datetime" => DateTime.to_iso8601(dt1),
                       "topWords" => [
                         %{
                           "project" => nil,
                           "score" => 82.0,
                           "word" => "word",
                           "context" => [
                             %{"score" => 1.0, "word" => "tight"},
                             %{"score" => 0.82, "word" => "short"}
                           ],
                           "summary" => "Third summary"
                         },
                         %{
                           "project" => %{"slug" => "bitcoin"},
                           "score" => 74.5,
                           "word" => "btc",
                           "context" => [
                             %{"score" => 1.0, "word" => "bitcoin"},
                             %{"score" => 0.63, "word" => "eth"}
                           ],
                           "summary" => "Another summary"
                         },
                         %{
                           "project" => %{"slug" => "ethereum"},
                           "score" => 72.4,
                           "word" => "eth",
                           "context" => [
                             %{"score" => 1.0, "word" => "halving"},
                             %{"score" => 0.85, "word" => "btc"}
                           ],
                           "summary" => "The summary"
                         }
                       ]
                     }
                   ]
                 }
               }
      end)
    end

    test "error", context do
      %{dt1: dt1, dt2: dt2} = context

      Sanbase.Mock.prepare_mock2(
        &SocialData.TrendingWords.get_trending_words/6,
        {:error, "Something broke"}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        args = %{from: dt1, to: dt2, interval: "1h", size: 10}

        query = trending_words_query(args)

        error_msg =
          execute(context.conn, query)
          |> get_error_message()

        assert error_msg =~ "Something broke"
      end)
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
        get_word_trending_history: fn _, _, _, _, _, _ -> {:ok, success_response} end do
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
        get_word_trending_history: fn _, _, _, _, _, _ -> {:error, "Something went wrong"} end do
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
        get_project_trending_history: fn _, _, _, _, _, _ -> {:ok, success_response} end do
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
        get_word_trending_history: fn _, _, _, _, _, _ -> {:error, "Something went wrong"} end do
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
            project{ slug }
            score
            summary
            context{
              word
              score
            }
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

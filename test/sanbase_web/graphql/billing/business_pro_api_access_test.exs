defmodule SanbaseWeb.Graphql.Billing.BusinessProApiAccessTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.Apikey
  alias Sanbase.Billing.Plan.StandardAccessChecker
  alias Sanbase.Metric
  alias Sanbase.SocialData.TrendingWords

  @mask_env "MASK_FIRST_3_WORDS_FREE_USER"
  @business_pro_history_days 2 * 365

  setup do
    # Masking applies only to FREE. Turning it on makes the tests fail if a
    # Business Pro request is ever treated as FREE.
    previous_mask_env = System.get_env(@mask_env)
    System.put_env(@mask_env, "true")

    on_exit(fn ->
      case previous_mask_env do
        nil -> System.delete_env(@mask_env)
        value -> System.put_env(@mask_env, value)
      end
    end)

    business_pro_user = insert(:user)
    insert(:subscription_business_pro_monthly, user: business_pro_user)
    {:ok, business_pro_apikey} = Apikey.generate_apikey(business_pro_user)

    free_user = insert(:user)
    {:ok, free_apikey} = Apikey.generate_apikey(free_user)

    [
      conn: setup_apikey_auth(build_conn(), business_pro_apikey),
      free_conn: setup_apikey_auth(build_conn(), free_apikey),
      project: insert(:random_erc20_project)
    ]
  end

  describe "getTrendingWords with Business Pro" do
    test "no word, summary or document is masked", context do
      {from, to} = from_to(1, 0)

      Sanbase.Mock.prepare_mock2(
        &TrendingWords.get_trending_words/6,
        {:ok, trending_words_response(from)}
      )
      |> Sanbase.Mock.prepare_mock2(&Req.get/2, documents_response())
      |> Sanbase.Mock.run_with_mocks(fn ->
        top_words = get_top_words(context.conn, from, to)

        assert Enum.map(top_words, & &1["word"]) == ["word1", "word2", "word3", "word4"]

        for word <- top_words do
          assert word["summary"] == "#{word["word"]} summary"
          assert word["bullishSummary"] == "#{word["word"]} bullish summary"
          assert word["bearishSummary"] == "#{word["word"]} bearish summary"
          refute inspect(word) =~ "***"
        end

        assert [%{"word" => "word1", "topDocuments" => [document]} | _] = top_words
        assert %{"text" => "word1 document", "screenName" => "santiment"} = document
      end)
    end

    test "is not masked when a FREE user made the same request first", context do
      {from, to} = from_to(1, 0)

      Sanbase.Mock.prepare_mock2(
        &TrendingWords.get_trending_words/6,
        {:ok, trending_words_response(from)}
      )
      |> Sanbase.Mock.prepare_mock2(&Req.get/2, documents_response())
      |> Sanbase.Mock.run_with_mocks(fn ->
        free_top_words = get_top_words(context.free_conn, from, to)
        assert Enum.map(free_top_words, & &1["word"]) == ["***", "***", "***", "word4"]

        top_words = get_top_words(context.conn, from, to)
        assert Enum.map(top_words, & &1["word"]) == ["word1", "word2", "word3", "word4"]
      end)
    end

    test "trending stories are not masked when a FREE user made the same request first",
         context do
      {from, to} = from_to(1, 0)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.SocialData.TrendingStories.get_trending_stories/5,
        {:ok, trending_stories_response(from)}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        free_titles = get_top_story_titles(context.free_conn, from, to)
        assert free_titles == ["***", "***", "***", "story4"]

        titles = get_top_story_titles(context.conn, from, to)
        assert titles == ["story1", "story2", "story3", "story4"]
      end)
    end

    test "realtime data and 2 years of history are passed through unchanged", context do
      {from, to} = from_to(@business_pro_history_days - 5, 0)

      calls = capture_trending_words_calls(fn -> get_top_words(context.conn, from, to) end)

      assert calls == [{from, to}]
    end

    test "history older than 2 years is cut off, realtime is kept", context do
      {from, to} = from_to(3 * 365, 0)

      [{called_from, called_to}] =
        capture_trending_words_calls(fn -> get_top_words(context.conn, from, to) end)

      assert called_to == to
      assert_about_days_ago(called_from, @business_pro_history_days)
    end

    test "gets more history than FREE for the same request", context do
      {from, to} = from_to(500, 0)

      [{free_from, free_to}] =
        capture_trending_words_calls(fn -> get_top_words(context.free_conn, from, to) end)

      [{business_pro_from, business_pro_to}] =
        capture_trending_words_calls(fn -> get_top_words(context.conn, from, to) end)

      assert_about_days_ago(free_from, 365)
      assert free_to == to

      assert business_pro_from == from
      assert business_pro_to == to
    end
  end

  describe "metrics with Business Pro" do
    test "every metric is accessible, except the ones with min plan MAX", context do
      restrictions = get_metric_access_restrictions(context.conn)

      assert restrictions != []

      for %{"isAccessible" => false, "name" => name} <- restrictions do
        assert StandardAccessChecker.min_plan("SANAPI", {:metric, name}) == "MAX",
               "#{name} is not accessible with Business Pro but its min plan is not MAX"
      end
    end

    test "restricted metrics have 2 years of history and no realtime cut-off", context do
      restricted =
        context.conn
        |> get_metric_access_restrictions()
        |> Enum.filter(&(&1["isAccessible"] and &1["isRestricted"]))

      assert restricted != []

      for restriction <- restricted do
        assert restriction["restrictedTo"] == nil

        restriction["restrictedFrom"]
        |> Sanbase.Utils.DateTime.from_iso8601!()
        |> assert_about_days_ago(@business_pro_history_days)
      end
    end

    test "a metric with min plan PRO is fetched with realtime data", context do
      metric = "withdrawal_balance"
      assert StandardAccessChecker.min_plan("SANAPI", {:metric, metric}) == "PRO"

      {from, to} = from_to(@business_pro_history_days - 5, 0)
      selector = extend_selector_with_required_fields(metric, %{slug: context.project.slug})
      test_pid = self()

      Sanbase.Mock.prepare_mock(Metric, :timeseries_data, fn
        ^metric, _selector, from, to, _interval, _opts ->
          send(test_pid, {:timeseries_data_called, from, to})
          {:ok, [%{datetime: from, value: 1.0}, %{datetime: to, value: 2.0}]}
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          context.conn
          |> post("/graphql", query_skeleton(metric_query(metric, selector, from, to)))
          |> json_response(200)

        refute Map.has_key?(result, "errors")

        assert get_in(result, ["data", "getMetric", "timeseriesData"]) == [
                 %{"datetime" => DateTime.to_iso8601(from), "value" => 1.0},
                 %{"datetime" => DateTime.to_iso8601(to), "value" => 2.0}
               ]

        assert_received {:timeseries_data_called, ^from, ^to}
      end)
    end
  end

  # Private functions

  defp capture_trending_words_calls(fun) do
    test_pid = self()

    Sanbase.Mock.prepare_mock(TrendingWords, :get_trending_words, fn
      from, to, _interval, _size, _source, _filter ->
        send(test_pid, {:trending_words_called, from, to})
        {:ok, %{}}
    end)
    |> Sanbase.Mock.run_with_mocks(fun)

    collect_trending_words_calls([])
  end

  defp collect_trending_words_calls(acc) do
    receive do
      {:trending_words_called, from, to} -> collect_trending_words_calls([{from, to} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # The cut-off is computed from the current time inside the request, so allow for
  # the time the test took to get there.
  defp assert_about_days_ago(datetime, days) do
    expected = Timex.shift(DateTime.utc_now(), days: -days)
    assert abs(DateTime.diff(datetime, expected, :second)) < 60
  end

  defp trending_words_response(datetime) do
    words =
      for {word, score} <- [{"word1", 90.0}, {"word2", 80.0}, {"word3", 70.0}, {"word4", 60.0}] do
        %{
          word: word,
          slug: nil,
          score: score,
          context: [],
          top_documents_ids: if(word == "word1", do: ["1"], else: []),
          summary: "#{word} summary",
          bullish_summary: "#{word} bullish summary",
          bearish_summary: "#{word} bearish summary",
          summaries: []
        }
      end

    %{datetime => words}
  end

  defp documents_response() do
    documents = [
      %{
        "doc_id" => "1",
        "text" => "word1 document",
        "source" => "twitter",
        "screen_name" => "santiment",
        "link_url" => nil
      }
    ]

    {:ok, %Req.Response{status: 200, body: %{"data" => Jason.encode!(documents)}}}
  end

  defp trending_stories_response(datetime) do
    stories =
      for {title, score} <- [
            {"story1", 90.0},
            {"story2", 80.0},
            {"story3", 70.0},
            {"story4", 60.0}
          ] do
        %{
          title: title,
          score: score,
          search_text: title,
          related_tokens: [],
          summary: "#{title} summary",
          bullish_ratio: 0.5,
          bearish_ratio: 0.5
        }
      end

    %{datetime => stories}
  end

  defp get_top_story_titles(conn, from, to) do
    query = """
    {
      getTrendingStories(from: "#{from}", to: "#{to}", interval: "1d", size: 10) {
        topStories { title summary }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    refute Map.has_key?(result, "errors")

    result
    |> get_in(["data", "getTrendingStories"])
    |> Enum.flat_map(& &1["topStories"])
    |> Enum.map(& &1["title"])
  end

  defp get_top_words(conn, from, to) do
    query = """
    {
      getTrendingWords(from: "#{from}", to: "#{to}", interval: "1d", size: 10) {
        datetime
        topWords {
          word
          score
          summary
          bullishSummary
          bearishSummary
          topDocuments { text screenName source }
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    refute Map.has_key?(result, "errors")

    result
    |> get_in(["data", "getTrendingWords"])
    |> Enum.flat_map(& &1["topWords"])
  end

  defp get_metric_access_restrictions(conn) do
    query = """
    {
      getAccessRestrictions(plan: BUSINESS_PRO, product: SANAPI, filter: METRIC) {
        name
        isAccessible
        isRestricted
        restrictedFrom
        restrictedTo
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getAccessRestrictions"])
  end

  defp metric_query(metric, selector, from, to) do
    """
    {
      getMetric(metric: "#{metric}") {
        timeseriesData(
          selector: #{map_to_input_object_str(selector)}
          from: "#{from}"
          to: "#{to}"
          interval: "1d"
          includeIncompleteData: true) {
            datetime
            value
        }
      }
    }
    """
  end
end

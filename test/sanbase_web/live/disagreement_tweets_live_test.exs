defmodule SanbaseWeb.DisagreementTweetsLiveTest do
  use SanbaseWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import SanbaseWeb.DisagreementTweetComponents

  alias Sanbase.DisagreementTweets

  describe "disagreement tweets context" do
    test "update_asset_direction succeeds for completed prediction tweets" do
      # Create a tweet that's completed and classified as prediction
      {:ok, tweet} =
        DisagreementTweets.create_classified_tweet(%{
          tweet_id: "test_123",
          timestamp: ~N[2025-01-18 10:00:00],
          screen_name: "test_user",
          text: "Test prediction tweet",
          url: "https://twitter.com/test/123",
          agreement: false,
          review_required: true,
          classification_count: 5,
          experts_is_prediction: true
        })

      attrs = %{
        prediction_direction: "up",
        base_asset: "BTC",
        quote_asset: "USD"
      }

      assert {:ok, updated_tweet} =
               DisagreementTweets.update_asset_direction(tweet.tweet_id, attrs)

      assert updated_tweet.prediction_direction == "up"
      assert updated_tweet.base_asset == "BTC"
      assert updated_tweet.quote_asset == "USD"
    end

    test "update_asset_direction fails for incomplete tweets" do
      {:ok, tweet} =
        DisagreementTweets.create_classified_tweet(%{
          tweet_id: "test_456",
          timestamp: ~N[2025-01-18 10:00:00],
          screen_name: "test_user",
          text: "Test prediction tweet",
          url: "https://twitter.com/test/456",
          agreement: false,
          review_required: true,
          classification_count: 3,
          experts_is_prediction: nil
        })

      attrs = %{
        prediction_direction: "up",
        base_asset: "BTC"
      }

      assert {:error, :not_eligible} =
               DisagreementTweets.update_asset_direction(tweet.tweet_id, attrs)
    end

    test "update_asset_direction fails for completed non-prediction tweets" do
      {:ok, tweet} =
        DisagreementTweets.create_classified_tweet(%{
          tweet_id: "test_789",
          timestamp: ~N[2025-01-18 10:00:00],
          screen_name: "test_user",
          text: "Test non-prediction tweet",
          url: "https://twitter.com/test/789",
          agreement: false,
          review_required: true,
          classification_count: 5,
          experts_is_prediction: false
        })

      attrs = %{
        prediction_direction: "up",
        base_asset: "BTC"
      }

      assert {:error, :not_eligible} =
               DisagreementTweets.update_asset_direction(tweet.tweet_id, attrs)
    end

    test "has_asset_direction? returns true when prediction_direction is set" do
      tweet = %{prediction_direction: "up", base_asset: nil, quote_asset: nil}
      assert DisagreementTweets.has_asset_direction?(tweet)
    end

    test "has_asset_direction? returns true when base_asset is set" do
      tweet = %{prediction_direction: nil, base_asset: "BTC", quote_asset: nil}
      assert DisagreementTweets.has_asset_direction?(tweet)
    end

    test "has_asset_direction? returns false when no asset direction fields are set" do
      tweet = %{prediction_direction: nil, base_asset: nil, quote_asset: nil}
      refute DisagreementTweets.has_asset_direction?(tweet)
    end

    test "search_project_tickers returns empty list for short queries" do
      assert DisagreementTweets.search_project_tickers("B") == []
    end

    test "search_project_tickers returns matching tickers for valid queries" do
      # This test assumes there are projects with tickers in the test DB
      tickers = DisagreementTweets.search_project_tickers("BTC")
      assert is_list(tickers)
      # Respects limit
      assert length(tickers) <= 10
    end

    test "search_project_tickers uses cached fuzzy search" do
      # Test fuzzy matching capabilities
      tickers = DisagreementTweets.search_project_tickers("bitco")
      assert is_list(tickers)

      # Test that exact matches are prioritized
      tickers_btc = DisagreementTweets.search_project_tickers("BTC")

      if length(tickers_btc) > 0 do
        assert List.first(tickers_btc) == "BTC" or
                 String.contains?(List.first(tickers_btc), "BTC")
      end
    end

    test "get_project_tickers returns list of tickers" do
      tickers = DisagreementTweets.get_project_tickers()
      assert is_list(tickers)
    end
  end

  describe "project cache functionality" do
    alias Sanbase.Project.ProjectCache

    test "search_projects returns empty list for short queries" do
      assert ProjectCache.search_projects("B") == []
    end

    test "search_projects returns results for valid queries" do
      results = ProjectCache.search_projects("BTC", 5)
      assert is_list(results)
      assert length(results) <= 5
    end

    test "get_cached_projects returns project data" do
      projects = ProjectCache.get_cached_projects()
      assert is_list(projects)

      if length(projects) > 0 do
        project = List.first(projects)
        assert Map.has_key?(project, :name)
        assert Map.has_key?(project, :ticker)
        assert Map.has_key?(project, :slug)
      end
    end

    test "clear_cache works without errors" do
      assert :ok = ProjectCache.clear_cache()
    end
  end

  describe "disagreement_tweet_card component" do
    test "shows AI classification when show_results is true regardless of classification count" do
      tweet = %{
        tweet_id: "123",
        screen_name: "test_user",
        timestamp: ~N[2025-01-18 10:00:00],
        classification_count: 2,
        experts_is_prediction: nil,
        url: "https://twitter.com/test/123",
        text: "Test tweet content",
        agreement: false,
        llama_is_prediction: true,
        llama_prob_true: 0.8,
        openai_is_prediction: false,
        openai_prob_true: 0.3,
        classifications: [],
        prediction_direction: nil,
        base_asset: nil,
        quote_asset: nil
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: true,
        show_asset_direction_form: false,
        user_id: 1
      }

      html =
        render_component(&disagreement_tweet_card/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "AI Model Comparison"
      assert html =~ "Expert Classifications"
      assert html =~ "Inhouse model"
      assert html =~ "OpenAI"
    end

    test "does not show AI classification when show_results is false and classification count < 5" do
      tweet = %{
        tweet_id: "123",
        screen_name: "test_user",
        timestamp: ~N[2025-01-18 10:00:00],
        classification_count: 2,
        experts_is_prediction: nil,
        url: "https://twitter.com/test/123",
        text: "Test tweet content",
        agreement: false,
        llama_is_prediction: true,
        llama_prob_true: 0.8,
        openai_is_prediction: false,
        openai_prob_true: 0.3,
        classifications: [],
        prediction_direction: nil,
        base_asset: nil,
        quote_asset: nil
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: false,
        show_asset_direction_form: false,
        user_id: 1
      }

      html =
        render_component(&disagreement_tweet_card/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      refute html =~ "AI Model Comparison"
      refute html =~ "Expert Classifications"
    end

    test "shows AI classification when classification count >= 5 regardless of show_results" do
      tweet = %{
        tweet_id: "123",
        screen_name: "test_user",
        timestamp: ~N[2025-01-18 10:00:00],
        classification_count: 5,
        experts_is_prediction: true,
        url: "https://twitter.com/test/123",
        text: "Test tweet content",
        agreement: false,
        llama_is_prediction: true,
        llama_prob_true: 0.8,
        openai_is_prediction: false,
        openai_prob_true: 0.3,
        classifications: [],
        prediction_direction: nil,
        base_asset: nil,
        quote_asset: nil
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: false,
        show_asset_direction_form: false,
        user_id: 1
      }

      html =
        render_component(&disagreement_tweet_card/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "AI Model Comparison"
      assert html =~ "Expert Classifications"
      assert html =~ "✅ PREDICTION"
    end

    test "shows asset direction form when show_asset_direction_form is true and no asset info exists" do
      tweet = %{
        tweet_id: "123",
        screen_name: "test_user",
        timestamp: ~N[2025-01-18 10:00:00],
        classification_count: 5,
        experts_is_prediction: true,
        url: "https://twitter.com/test/123",
        text: "Test tweet content",
        agreement: false,
        llama_is_prediction: true,
        llama_prob_true: 0.8,
        openai_is_prediction: false,
        openai_prob_true: 0.3,
        classifications: [],
        prediction_direction: nil,
        base_asset: nil,
        quote_asset: nil
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: true,
        show_asset_direction_form: true,
        user_id: 1
      }

      html =
        render_component(&disagreement_tweet_card/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "Asset Direction Information"
      assert html =~ "Prediction Direction"
      assert html =~ "Base Asset"
      assert html =~ "Quote Asset"
      assert html =~ "Add Asset Direction"
    end

    test "shows asset direction display when asset info exists" do
      tweet = %{
        tweet_id: "123",
        screen_name: "test_user",
        timestamp: ~N[2025-01-18 10:00:00],
        classification_count: 5,
        experts_is_prediction: true,
        url: "https://twitter.com/test/123",
        text: "Test tweet content",
        agreement: false,
        llama_is_prediction: true,
        llama_prob_true: 0.8,
        openai_is_prediction: false,
        openai_prob_true: 0.3,
        classifications: [],
        prediction_direction: "up",
        base_asset: "BTC",
        quote_asset: "USD"
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: true,
        show_asset_direction_form: true,
        user_id: 1
      }

      html =
        render_component(&disagreement_tweet_card/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "Asset Direction Information"
      assert html =~ "📈 Up"
      assert html =~ "BTC"
      assert html =~ "USD"
      refute html =~ "Add Asset Direction"
    end

    test "does not show asset direction form when show_asset_direction_form is false" do
      tweet = %{
        tweet_id: "123",
        screen_name: "test_user",
        timestamp: ~N[2025-01-18 10:00:00],
        classification_count: 5,
        experts_is_prediction: true,
        url: "https://twitter.com/test/123",
        text: "Test tweet content",
        agreement: false,
        llama_is_prediction: true,
        llama_prob_true: 0.8,
        openai_is_prediction: false,
        openai_prob_true: 0.3,
        classifications: [],
        prediction_direction: nil,
        base_asset: nil,
        quote_asset: nil
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: true,
        show_asset_direction_form: false,
        user_id: 1
      }

      html =
        render_component(&disagreement_tweet_card/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      refute html =~ "Asset Direction Information"
    end
  end
end

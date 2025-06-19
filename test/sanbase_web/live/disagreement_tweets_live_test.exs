defmodule SanbaseWeb.DisagreementTweetsLiveTest do
  use SanbaseWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import SanbaseWeb.DisagreementTweetComponents

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
        classifications: []
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: true,
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
        classifications: []
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: false,
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
        classifications: []
      }

      assigns = %{
        tweet: tweet,
        show_classification_buttons: false,
        show_results: false,
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
  end
end

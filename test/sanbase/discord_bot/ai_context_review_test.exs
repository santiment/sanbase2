defmodule Sanbase.DiscordBot.AiContextReviewTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.AiContextReview

  @base_params %{
    discord_user: "someone",
    guild_id: "852836083381174282",
    guild_name: "Santiment",
    channel_id: "854002386375934033",
    channel_name: "general",
    thread_id: "1564953330311110757",
    command: "!ai",
    question: "Why did the crypto market drop over the last 3 days?",
    answer: "The market fell on Fed uncertainty and ETF outflows."
  }

  defp create(params \\ %{}) do
    {:ok, context} = AiContext.create(Map.merge(@base_params, params))
    context
  end

  defp flags(params), do: params |> create() |> AiContextReview.flags_for()

  describe "flags_for/1" do
    test "a clean turn has no flags" do
      assert flags(%{elapsed_time: 12.0, delivery_status: "sent"}) == []
    end

    test "flags each problem the row records" do
      assert flags(%{delivery_status: "failed"}) == ["delivery_failed"]
      assert flags(%{status: "error", answer: nil}) == ["error"]
      assert flags(%{status: "degraded"}) == ["degraded"]
      assert flags(%{tool_issues: ["search_tweets:empty"]}) == ["tool_issue"]
      assert flags(%{votes: %{"123" => -1}}) == ["downvoted"]
      assert flags(%{votes: %{"123" => 1}}) == []
      assert flags(%{elapsed_time: 75.0}) == ["slow"]
    end

    test "flags an English question answered in Cyrillic" do
      # Regression: an English question was answered in Russian on 2026-10-28.
      assert flags(%{answer: "Коротко: падение было вызвано ожиданием решения ФРС."}) ==
               ["language_mismatch"]
    end
  end

  describe "language_mismatch?/2" do
    test "ignores URLs and tickers in the answer" do
      refute AiContextReview.language_mismatch?(
               "Защо пазарът падна през последните три дни?",
               "Пазарът падна заради ФРС и изтичане от ETF: https://x.com/user/status/1 BTC"
             )
    end

    test "ignores questions too short to tell the language" do
      refute AiContextReview.language_mismatch?("BTC?", "Биткойн е на 80 000 долара.")
    end

    test "is false when there is no answer" do
      refute AiContextReview.language_mismatch?("What is MVRV ratio exactly?", nil)
    end
  end

  describe "list/3 and select/2" do
    test "keeps the platform and flag filters apart from the counts" do
      flagged_discord = create(%{delivery_status: "failed"})
      _clean_discord = create()
      flagged_telegram = create(%{guild_id: "tg_-100123", tool_issues: ["search_tweets:empty"]})

      filters = AiContextReview.parse_filters(%{})
      all_rows = AiContextReview.list_for_filters(filters)

      assert length(all_rows) == 3

      assert AiContextReview.flag_counts(all_rows) |> Map.take(["delivery_failed", "tool_issue"]) ==
               %{"delivery_failed" => 1, "tool_issue" => 1}

      assert all_rows |> AiContextReview.select(filters) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([flagged_discord.id, flagged_telegram.id])

      telegram_filters = AiContextReview.parse_filters(%{"platform" => "telegram"})

      assert [%{id: id}] = AiContextReview.list_for_filters(telegram_filters)
      assert id == flagged_telegram.id

      flag_filters = AiContextReview.parse_filters(%{"flag" => "delivery_failed"})

      assert [%{id: flagged_id}] =
               flag_filters
               |> AiContextReview.list_for_filters()
               |> AiContextReview.select(flag_filters)

      assert flagged_id == flagged_discord.id
    end

    test "parse_filters/1 falls back to yesterday and today" do
      today = Date.utc_today()

      assert %{from: from, to: ^today, platform: "", flag: "", flagged_only: true} =
               AiContextReview.parse_filters(%{"from" => "not a date", "flag" => "bogus"})

      assert from == Date.add(today, -1)
    end
  end

  test "to_jsonl/1 writes one decodable object per row" do
    create(%{delivery_status: "failed", langfuse_trace_id: "78b51dcb"})

    filters = AiContextReview.parse_filters(%{})
    jsonl = filters |> AiContextReview.list_for_filters() |> AiContextReview.to_jsonl()

    assert [line] = String.split(jsonl, "\n", trim: true)
    row = Jason.decode!(line)

    assert row["flags"] == ["delivery_failed"]
    assert row["platform"] == "discord"
    assert row["langfuse_trace_id"] == "78b51dcb"
    assert row["question"] == @base_params.question
  end

  describe "AiContext.record_delivery/2" do
    test "marks a posted answer as sent" do
      {:ok, context} = AiContext.record_delivery(create(), :ok)
      assert context.delivery_status == "sent"
      assert context.delivery_error == nil
    end

    test "keeps the reason a post failed" do
      {:ok, context} =
        AiContext.record_delivery(create(), {:error, %Jason.EncodeError{message: "invalid byte"}})

      assert context.delivery_status == "failed"
      assert context.delivery_error =~ "invalid byte"
    end
  end
end

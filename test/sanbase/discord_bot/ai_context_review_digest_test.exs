defmodule Sanbase.DiscordBot.AiContextReviewDigestTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.AiContextReview
  alias Sanbase.DiscordBot.AiContextReviewDigest

  @base_params %{
    discord_user: "someone",
    guild_id: "852836083381174282",
    guild_name: "Santiment",
    channel_id: "854002386375934033",
    channel_name: "general",
    thread_id: "1564953330311110757",
    command: "!ai",
    question: "Why did the crypto market drop over the last 3 days?",
    answer: "The market fell on Fed uncertainty and ETF outflows.",
    elapsed_time: 12.0
  }

  defp create(params) do
    {:ok, context} = AiContext.create(Map.merge(@base_params, params))
    context
  end

  defp window() do
    to = NaiveDateTime.utc_now() |> NaiveDateTime.add(60, :second)
    {NaiveDateTime.add(to, -24 * 3600, :second), to}
  end

  describe "build/3" do
    test "counts the turns per flag and lists the flagged ones with their trace" do
      create(%{})

      create(%{
        guild_id: "tg_-1001140094437",
        discord_user: "tg:balance54",
        question: "Ok, do the same for the top 200",
        tool_issues: ["fetch_metric_data_tool:error"],
        votes: %{"tg:balance54" => -1},
        langfuse_trace_id: "f3be602d-761d-423a-b66d-e9ace00ea14c"
      })

      {from, to} = window()
      {subject, body} = AiContextReviewDigest.build(AiContextReview.list(from, to), from, to)

      assert subject =~ "1 flagged of 2 turns"
      assert body =~ "Tool issue: 1"
      assert body =~ "Downvoted: 1"
      assert body =~ "Error: 0"
      assert body =~ "telegram tg:balance54 [Tool issue, Downvoted]"
      assert body =~ "  Ok, do the same for the top 200"
      assert body =~ "/traces/f3be602d-761d-423a-b66d-e9ace00ea14c"
      assert body =~ "/admin/ai_bot_review?from="
      # The clean turn is counted but not listed.
      refute body =~ "Why did the crypto market drop"
    end

    test "says there is nothing flagged without listing turns" do
      create(%{})

      {from, to} = window()
      {subject, body} = AiContextReviewDigest.build(AiContextReview.list(from, to), from, to)

      assert subject =~ "0 flagged of 1 turns"
      refute body =~ "Flagged turns"
    end
  end

  test "send_digest/1 emails the digest to the reviewer" do
    create(%{status: "error", answer: nil})

    Sanbase.Mock.prepare_mock(Sanbase.SimpleMailer, :send_email, fn rcpt, subject, body ->
      send(self(), {:email, rcpt, subject, body})
      {:ok, :sent}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      # The window ends at `now`; move it past the row written this second.
      assert {:ok, :sent} =
               AiContextReviewDigest.send_digest(DateTime.add(DateTime.utc_now(), 60))

      assert_receive {:email, rcpt, subject, body}
      assert rcpt == AiContextReviewDigest.recipient()
      assert subject =~ "1 flagged of 1 turns"
      assert body =~ "[Error]"
    end)
  end

  test "maybe_send/0 does not send outside prod" do
    assert AiContextReviewDigest.maybe_send() == :skipped
  end
end

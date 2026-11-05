defmodule Sanbase.DiscordBot.AiReviewIssuesTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory, only: [insert: 1]

  alias Sanbase.DiscordBot.{AiContext, AiReviewIssue, AiReviewIssues}
  alias Sanbase.Repo

  @base_params %{
    discord_user: "someone",
    guild_id: "tg_-1001140094437",
    guild_name: "Santiment",
    channel_id: "854002386375934033",
    channel_name: "general",
    thread_id: "tg_-1001140094437_m96763",
    command: "!ai",
    question: "Ok, do the same for the top 200",
    answer: "I can't give a reliable top-200 list for that window.",
    elapsed_time: 12.0
  }

  defp create(params) do
    {:ok, context} = AiContext.create(Map.merge(@base_params, params))
    context
  end

  defp issue(signature), do: Repo.get_by(AiReviewIssue, signature: signature)

  describe "signatures/1" do
    test "gives one signature per tool issue and normalizes messages" do
      context = %AiContext{
        id: 7,
        question: "Why did the market drop?",
        answer: "Because of the Fed.",
        status: "error",
        error_message: "ai_server_http_502 after 30000 ms",
        tool_issues: ["fetch_metric_data_tool:error", "search_tweets:empty"],
        votes: %{"tg:x" => -1}
      }

      assert AiReviewIssues.signatures(context) == [
               {"error:ai_server_http_N after N ms", "error"},
               {"tool_issue:fetch_metric_data_tool:error", "tool_issue"},
               {"tool_issue:search_tweets:empty", "tool_issue"},
               {"downvoted:7", "downvoted"}
             ]
    end

    test "a clean turn has no signatures" do
      assert AiReviewIssues.signatures(%AiContext{question: "hi", answer: "hello"}) == []
    end
  end

  describe "recording" do
    test "a written turn creates its issues right away" do
      context = create(%{tool_issues: ["fetch_metric_data_tool:error"]})

      issue = issue("tool_issue:fetch_metric_data_tool:error")
      assert %AiReviewIssue{status: "open", flag: "tool_issue", occurrences: 1} = issue
      assert issue.last_ai_context_id == context.id
    end

    test "turns with the same problem share one issue, each counted once" do
      first = create(%{tool_issues: ["fetch_metric_data_tool:error"]})
      second = create(%{tool_issues: ["fetch_metric_data_tool:error"]})

      # Recording a turn again (e.g. a later vote) does not count it twice.
      assert AiReviewIssues.record(first) == :ok

      issue = issue("tool_issue:fetch_metric_data_tool:error")
      assert issue.occurrences == 2
      assert issue.last_ai_context_id == second.id
    end

    test "a failed delivery and a downvote added later create issues" do
      context = create(%{})

      {:ok, context} =
        AiContext.record_delivery(context, {:error, "Bad Request: message is too long"})

      {:ok, _} = AiContext.add_vote(context.id, %{"tg:balance54" => -1})

      assert issue("delivery_failed:Bad Request: message is too long")
      assert issue("downvoted:#{context.id}")
    end
  end

  describe "resolve and recur" do
    test "a resolved issue becomes recurred when a newer turn shows it" do
      user = insert(:user)
      create(%{tool_issues: ["fetch_metric_data_tool:error"]})
      issue = issue("tool_issue:fetch_metric_data_tool:error")

      {:ok, issue} = AiReviewIssues.resolve(issue, user, "Fixed slug check, PR 5413")
      assert issue.status == "resolved"
      assert issue.resolved_by_id == user.id

      # Back-date the resolution so the next turn is clearly after it.
      Repo.update_all(AiReviewIssue, set: [resolved_at: ~U[2020-01-01 00:00:00Z]])

      create(%{tool_issues: ["fetch_metric_data_tool:error"]})

      issue = issue("tool_issue:fetch_metric_data_tool:error")
      assert issue.status == "recurred"
      assert issue.recurrences == 1
      assert issue.resolution_note == "Fixed slug check, PR 5413"
    end

    test "a turn from before the resolution does not reopen it" do
      user = insert(:user)
      old = create(%{tool_issues: ["search_tweets:empty"]})
      {:ok, _} = AiReviewIssues.resolve(issue("tool_issue:search_tweets:empty"), user, nil)

      # E.g. a backfill that reaches turns written before the fix.
      Repo.update_all(AiContext, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      Repo.delete_all("ai_review_issue_turns")
      AiReviewIssues.record(Repo.get!(AiContext, old.id))

      assert issue("tool_issue:search_tweets:empty").status == "resolved"
    end
  end

  describe "list/1" do
    test "pages by the updated_at cursor and filters by status" do
      create(%{tool_issues: ["a:error"]})
      create(%{tool_issues: ["b:error"]})

      {[first], cursor} = AiReviewIssues.list(limit: 1)
      {[second], cursor} = AiReviewIssues.list(since: cursor, limit: 1)
      assert {[], ^cursor} = AiReviewIssues.list(since: cursor)
      assert [first.signature, second.signature] == ["tool_issue:a:error", "tool_issue:b:error"]

      {:ok, _} = AiReviewIssues.resolve(first, insert(:user), nil)
      {[changed], _} = AiReviewIssues.list(since: cursor)
      assert changed.id == first.id

      {open, _} = AiReviewIssues.list(statuses: ["open"])
      assert Enum.map(open, & &1.id) == [second.id]
    end
  end
end

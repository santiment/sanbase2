defmodule Sanbase.DiscordBot.AiContextTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.DiscordBot.AiContext

  @base_params %{
    discord_user: "tg:someone",
    guild_id: "tg_-100123",
    guild_name: "Santiment",
    channel_id: "-100123",
    channel_name: "Santiment",
    thread_id: "tg_-100123_m1",
    command: "!ai"
  }

  defp create(params) do
    {:ok, context} = AiContext.create(Map.merge(@base_params, params))
    context
  end

  describe "diagnostics columns" do
    test "a successful turn is stored as ok" do
      context = create(%{question: "what is MVRV?", answer: "MVRV is..."})

      assert context.status == "ok"
      assert context.v2_fallback == false
      assert context.tools_used == []
    end

    test "a degraded turn keeps the fields needed to find it later" do
      context =
        create(%{
          question: "какие монеты выросли за неделю?",
          answer: "partial answer",
          status: "degraded",
          qa_engine: "v2",
          v2_fallback: true,
          rephrased_question: "which tokens are whales accumulating?",
          tools_used: ["resolve_metric", "assets_by_metric_tool"],
          langfuse_trace_id: "d70be0fa-63e2-452a-8e79-446238afc8c6",
          error_message: "RuntimeError: upstream 500"
        })

      assert context.status == "degraded"
      assert context.qa_engine == "v2"
      assert context.v2_fallback
      assert context.rephrased_question == "which tokens are whales accumulating?"
      assert context.tools_used == ["resolve_metric", "assets_by_metric_tool"]
      assert context.langfuse_trace_id == "d70be0fa-63e2-452a-8e79-446238afc8c6"
      assert context.error_message == "RuntimeError: upstream 500"
    end

    test "an errored turn is stored even though it has no answer" do
      context =
        create(%{
          question: "первые 10 из списка",
          status: "error",
          error_message: "ai_server_http_500"
        })

      assert context.status == "error"
      assert is_nil(context.answer)
      assert context.id
    end

    test "an unknown status is rejected" do
      changeset =
        AiContext.changeset(
          %AiContext{},
          Map.merge(@base_params, %{question: "q", status: "wat"})
        )

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:status]
    end
  end

  describe "fetch_recent_history/2" do
    test "skips errored turns so a failure is not replayed into the next prompt" do
      create(%{question: "first", answer: "first answer"})
      create(%{question: "failed", status: "error", error_message: "ai_server_http_500"})
      create(%{question: "second", answer: "second answer"})

      questions =
        "tg_-100123_m1"
        |> AiContext.fetch_recent_history(10)
        |> Enum.map(& &1.question)

      assert "failed" not in questions
      assert Enum.sort(questions) == ["first", "second"]
    end

    test "keeps degraded turns, which the user did see" do
      create(%{question: "degraded", answer: "partial", status: "degraded"})

      assert ["degraded"] =
               "tg_-100123_m1"
               |> AiContext.fetch_recent_history(10)
               |> Enum.map(& &1.question)
    end

    test "skips a turn with no answer even when its status was never set" do
      create(%{question: "answered", answer: "yes"})
      create(%{question: "no answer at all", answer: nil, status: nil})

      assert ["answered"] =
               "tg_-100123_m1"
               |> AiContext.fetch_recent_history(10)
               |> Enum.map(& &1.question)
    end
  end

  describe "check_limits/1" do
    setup do
      %{args: %{guild_id: @base_params.guild_id, user_is_pro: false}}
    end

    test "errored turns do not consume the daily quota", %{args: args} do
      for i <- 1..12 do
        create(%{question: "failed #{i}", status: "error", error_message: "ai_server_http_500"})
      end

      assert :ok = AiContext.check_limits(args)
    end

    test "successful turns still consume the daily quota", %{args: args} do
      for i <- 1..10 do
        create(%{question: "ok #{i}", answer: "answer #{i}"})
      end

      assert {:error, :eserverlimit, _time_left} = AiContext.check_limits(args)
    end

    test "non-twitter questions count too", %{args: args} do
      # `command` is "!thread" for academy / metric / dialogue answers, which is
      # most of them. Counting only "!ai" meant the limit almost never applied.
      for i <- 1..10 do
        create(%{question: "metric #{i}", answer: "answer #{i}", command: "!thread"})
      end

      assert {:error, :eserverlimit, _time_left} = AiContext.check_limits(args)
    end

    test "degraded turns consume the quota, since the user got an answer", %{args: args} do
      for i <- 1..10 do
        create(%{question: "degraded #{i}", answer: "partial #{i}", status: "degraded"})
      end

      assert {:error, :eserverlimit, _time_left} = AiContext.check_limits(args)
    end
  end
end

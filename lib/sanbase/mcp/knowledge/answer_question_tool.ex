defmodule Sanbase.MCP.Knowledge.AnswerQuestionTool do
  @moduledoc """
  Get Santiment's own generated answer to a question, the same answer the Ask page gives,
  with citations.

  Use it only when explicitly asked for Santiment's generated answer. By default, call
  `search_knowledge` and write the answer yourself from the excerpts.
  """

  use Anubis.Server.Component, type: :tool

  require Logger

  alias Anubis.Server.Response
  alias Sanbase.Knowledge
  alias Sanbase.MCP.ToolError

  def name(), do: "answer_question"

  @impl true
  def annotations() do
    %{
      "title" => "Generate Answer",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:question, :string, required: true, description: "The user's question.")
  end

  @impl true
  def execute(params, frame) do
    question = params |> Map.get(:question, "") |> String.trim()

    if question == "" do
      {:reply, Response.error(Response.tool(), ToolError.permanent("`question` is empty")), frame}
    else
      do_execute(question, frame)
    end
  end

  defp do_execute(question, frame) do
    case Knowledge.answer_question(question, context_expansion: true) do
      {:ok, answer, plan} ->
        log_answer(question, answer, plan, true, nil, frame)
        {:reply, Response.json(Response.tool(), %{question: question, answer: answer}), frame}

      {:error, reason} ->
        Logger.warning("[MCP.Knowledge] answer_question failed: #{inspect(reason)}")
        log_answer(question, "Failed to generate an answer", nil, false, reason, frame)
        message = ToolError.transient("Generating the answer failed. Retry shortly.")
        {:reply, Response.error(Response.tool(), message), frame}
    end
  end

  defp log_answer(question, answer, plan, is_successful, errors, frame) do
    Sanbase.Knowledge.QuestionAnswerLog.create(%{
      question: question,
      answer: answer,
      question_type: "mcp_answer",
      source: "faq, insight, academy",
      is_successful: is_successful,
      errors: errors && inspect(errors),
      context_expansion: true,
      user_id: frame.assigns[:current_user] && frame.assigns.current_user.id,
      query_plan: plan && Sanbase.Knowledge.QueryPlan.to_map(plan)
    })
  end
end

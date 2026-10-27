defmodule Sanbase.MCP.Knowledge.Server do
  @moduledoc """
  Team-only MCP server for the knowledge base, served at `/mcp_knowledge`.
  `handle_request/2` re-checks access so a routing mistake cannot expose it.
  """

  use Anubis.Server,
    name: "santiment-knowledge",
    version: "1.0.0",
    capabilities: [:tools]

  alias Sanbase.MCP.Auth
  alias Sanbase.MCP.Knowledge.Access

  component(Sanbase.MCP.Knowledge.SearchKnowledgeTool)
  component(Sanbase.MCP.Knowledge.FetchEntryTool)
  component(Sanbase.MCP.Knowledge.AnswerQuestionTool)
  component(Sanbase.MCP.Knowledge.CreateFaqDraftTool)
  component(Sanbase.MCP.Knowledge.UpdateFaqDraftTool)

  @impl true
  def server_instructions() do
    """
    Santiment's internal knowledge base (FAQ, Academy articles, Insights) for the support team.

    To answer a user question:
    1. Call `search_knowledge` with the question. It returns numbered excerpts, not an answer.
    2. If an excerpt is cut short, call `fetch_entry` with its `type` and `id` for the full text.
    3. Write the answer yourself from the excerpts only, citing them as [n]. Say plainly what
       the knowledge base does not cover instead of filling gaps from general knowledge.
    Use `answer_question` only when explicitly asked for Santiment's own generated answer.

    When the knowledge base has no good answer and the team provides the missing information,
    offer to save it with `create_faq_draft`. Drafts are reviewed by a person before they are
    published, and are never used in answers until then.
    """
  end

  @impl true
  def init(_client_info, %Anubis.Server.Frame{} = frame) do
    {:ok, assign_current_user(frame)}
  end

  @impl true
  def handle_request(%{"method" => method} = request, %Anubis.Server.Frame{} = frame) do
    frame = assign_current_user(frame)

    if Access.allowed?(frame.assigns[:current_user]) or method == "ping" do
      Anubis.Server.Handlers.handle(request, __MODULE__, frame)
    else
      {:error, Anubis.MCP.Error.protocol(:invalid_request, %{message: Access.denied_message()}),
       frame}
    end
  end

  defp assign_current_user(%Anubis.Server.Frame{} = frame) do
    headers = frame.context.headers || []
    user = frame.assigns[:current_user] || Auth.headers_list_to_user(headers)

    frame
    |> assign(:current_user, user)
    |> assign(:is_authenticated, not is_nil(user))
  end
end

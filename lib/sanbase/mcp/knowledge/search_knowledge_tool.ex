defmodule Sanbase.MCP.Knowledge.SearchKnowledgeTool do
  @moduledoc """
  Search Santiment's knowledge base (FAQ, Academy, Insights) and return the most relevant
  excerpts, numbered [1], [2], ... You write the answer from them.

  This is the default way to answer a support question. Write the answer only from these
  excerpts, cite them inline as [n], and say what they do not cover. Each excerpt has a
  `type` and `id`; when `is_full_text` is false the text is an excerpt, and `fetch_entry`
  returns the whole document. Insight excerpts with `paywalled: true` come from paid
  content: summarize and link them rather than quoting them at length to a user.
  """

  use Anubis.Server.Component, type: :tool

  require Logger

  alias Anubis.Server.Response
  alias Sanbase.Knowledge
  alias Sanbase.Knowledge.Faq
  alias Sanbase.Knowledge.PlanRestrictions
  alias Sanbase.MCP.Knowledge.Format
  alias Sanbase.MCP.ToolError

  @sources ~w(faq academy insight)

  def name(), do: "search_knowledge"

  @impl true
  def annotations() do
    %{
      "title" => "Search Knowledge Base",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:question, :string,
      required: true,
      description: "The user's question, as close to their own words as possible."
    )

    field(:sources, {:list, :string},
      required: false,
      description:
        "Sources to search, any of #{inspect(@sources)}. Defaults to all three. " <>
          "Narrow it only when a source is clearly irrelevant."
    )

    field(:include_plan_restrictions, :boolean,
      required: false,
      description: """
      Include the authoritative SanAPI plan access-restriction table (default true). It is
      generated from the access-control code and wins over any excerpt that disagrees. Keep it on
      for questions about plans, API limits, missing or shortened historical data. Set it to
      false on follow-up searches once you already have it.
      """
    )

    field(:include_drafts, :boolean,
      required: false,
      description: """
      Also list unreviewed FAQ drafts similar to the question (default false). Drafts are not
      verified: use them to avoid duplicating a draft, never as a source for an answer.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    question = params |> Map.get(:question, "") |> String.trim()
    sources = params[:sources] || @sources

    with :ok <- validate_question(question),
         :ok <- validate_sources(sources),
         {:ok, context} <- retrieve(question, sources) do
      response =
        %{
          question: question,
          interpreted_as: plan_summary(context.plan),
          excerpts: excerpts(context.hits),
          plan_restrictions: plan_restrictions(params),
          drafts: drafts(context.embedding, params)
        }
        |> reject_nil_values()

      log_search(question, sources, response, frame)
      {:reply, Response.json(Response.tool(), response), frame}
    else
      {:error, message} -> {:reply, Response.error(Response.tool(), message), frame}
    end
  end

  defp validate_question(""), do: {:error, ToolError.permanent("`question` must not be empty")}
  defp validate_question(_), do: :ok

  defp validate_sources(sources) when is_list(sources) and sources != [] do
    case sources -- @sources do
      [] ->
        :ok

      unknown ->
        {:error,
         ToolError.permanent(
           "Unknown sources #{inspect(unknown)}. Valid sources: #{inspect(@sources)}"
         )}
    end
  end

  defp validate_sources(_),
    do:
      {:error, ToolError.permanent("`sources` must be a non-empty list of #{inspect(@sources)}")}

  defp retrieve(question, sources) do
    options = [
      faq: "faq" in sources,
      academy: "academy" in sources,
      insight: "insight" in sources,
      # Widen each matched chunk with its neighbours: the client model reads the
      # excerpts directly, so more continuous text gives better answers.
      context_expansion: true
    ]

    case Knowledge.retrieve_context(question, options) do
      {:ok, context} ->
        {:ok, context}

      {:error, reason} ->
        Logger.warning("[MCP.Knowledge] search_knowledge failed: #{inspect(reason)}")
        {:error, ToolError.transient("Knowledge search failed. Retry shortly.")}
    end
  end

  defp excerpts(hits) do
    Enum.flat_map([:faq, :insight, :academy], fn source ->
      hits |> Map.get(source, []) |> Enum.map(&Format.hit(&1, source))
    end)
  end

  defp plan_summary(plan) do
    %{
      search_text: plan.semantic_query,
      sort: to_string(plan.sort),
      date_from: plan.date_from && Date.to_iso8601(plan.date_from),
      date_to: plan.date_to && Date.to_iso8601(plan.date_to)
    }
  end

  defp plan_restrictions(params) do
    if Map.get(params, :include_plan_restrictions, true) != false do
      PlanRestrictions.render_inner_section()
    end
  end

  # Drafts similar to the question, searched directly (not as a filter over the
  # top entries of every status) and held to the same similarity floor as answers.
  defp drafts(embedding, params) do
    if params[:include_drafts] == true do
      {:ok, entries} = Faq.find_most_similar_faqs(embedding, 5, statuses: [:draft])
      min_similarity = Knowledge.default_min_similarity()

      entries
      |> Enum.filter(&(is_number(&1.similarity) and &1.similarity >= min_similarity))
      |> Enum.map(&Format.similar_faq/1)
    end
  end

  defp reject_nil_values(map), do: map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

  defp log_search(question, sources, response, frame) do
    answer =
      case response.excerpts do
        [] -> "No excerpts found"
        excerpts -> Enum.map_join(excerpts, "\n", &"[#{&1.n}] #{&1.type}: #{&1.title}")
      end

    Sanbase.Knowledge.QuestionAnswerLog.create(%{
      question: question,
      answer: answer,
      question_type: "mcp_search",
      source: Enum.join(sources, ", "),
      is_successful: true,
      context_expansion: true,
      user_id: frame.assigns[:current_user] && frame.assigns.current_user.id
    })
  end
end

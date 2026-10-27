defmodule Sanbase.MCP.Knowledge.CreateFaqDraftTool do
  @moduledoc """
  Save a new FAQ entry as a draft for a Santiment team member to review.

  Use it when the knowledge base had no good answer and the team supplied the missing
  information. Write the entry for future users, not for this one conversation: a general
  question, and a self-contained Markdown answer with no names, account details or
  conversation references. Put that context in `internal_notes` instead.

  The draft is never used in answers until a person publishes it in the admin panel.
  Near-duplicate entries are reported instead of creating a new draft: update the existing
  draft with `update_faq_draft`, or pass `force: true` only if the new entry is truly distinct.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.Knowledge.Faq
  alias Sanbase.Knowledge.FaqEntry
  alias Sanbase.MCP.Knowledge.Format
  alias Sanbase.MCP.ToolError

  def name(), do: "create_faq_draft"

  @impl true
  def annotations() do
    %{
      "title" => "Create FAQ Draft",
      "readOnlyHint" => false,
      "destructiveHint" => false,
      "idempotentHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:question, :string,
      required: true,
      description: "The question, phrased generally as future users would ask it."
    )

    field(:answer_markdown, :string,
      required: true,
      description: "The complete answer in Markdown, self-contained and free of personal details."
    )

    field(:tags, {:list, :string},
      required: false,
      description: "Optional tags, any of #{inspect(FaqEntry.allowed_tags())}."
    )

    field(:source_url, :string,
      required: false,
      description: "Optional http(s) link to where the answer came from, e.g. a Discord thread."
    )

    field(:internal_notes, :string,
      required: false,
      description: """
      Context for the reviewer, never shown to users: the original user question, who on the
      team provided the information, and anything the reviewer should double-check.
      """
    )

    field(:force, :boolean,
      required: false,
      description: "Create the draft even when near-duplicate entries exist (default false)."
    )
  end

  @impl true
  def execute(params, frame) do
    {:reply, params |> create(frame.assigns.current_user) |> to_response(), frame}
  end

  defp create(params, user) do
    attrs = Format.draft_attrs(params)

    with :ok <- validate_tags(attrs[:tags]),
         {:ok, entry} <- Faq.create_draft(user, attrs, force: params[:force] == true) do
      {:ok, Sanbase.Repo.preload(entry, [:created_by], force: true)}
    end
  end

  defp to_response({:ok, entry}) do
    Response.json(Response.tool(), %{
      created: true,
      message:
        "Draft saved. It is not used in answers until a team member reviews and publishes it " <>
          "at admin_url.",
      entry: Format.faq_entry(entry)
    })
  end

  defp to_response({:duplicates, duplicates}) do
    Response.json(Response.tool(), %{
      created: false,
      message:
        "Similar FAQ entries already exist. Compare them with the new entry: update an " <>
          "existing draft with `update_faq_draft`, or call again with `force: true` if the " <>
          "new entry is truly distinct. Published entries can only be changed in the admin panel.",
      similar_entries: Enum.map(duplicates, &Format.similar_faq/1)
    })
  end

  defp to_response({:error, :embedding_failed}) do
    Format.error_response(
      ToolError.transient("Could not save the draft right now. Retry shortly.")
    )
  end

  defp to_response({:error, reason}), do: Format.error_response(reason)

  @doc false
  def validate_tags(nil), do: :ok

  def validate_tags(tags) when is_list(tags) do
    case tags -- FaqEntry.allowed_tags() do
      [] ->
        :ok

      unknown ->
        {:error,
         ToolError.permanent(
           "Unknown tags #{inspect(unknown)}. Allowed tags: #{inspect(FaqEntry.allowed_tags())}"
         )}
    end
  end
end

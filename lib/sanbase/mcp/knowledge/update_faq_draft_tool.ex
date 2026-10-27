defmodule Sanbase.MCP.Knowledge.UpdateFaqDraftTool do
  @moduledoc """
  Revise an FAQ draft that has not been published yet, e.g. after more input from the team.

  Only the fields you pass are changed; `tags`, when given, replaces the whole tag list.
  Published entries cannot be changed here, only in the admin panel.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.Knowledge.Faq
  alias Sanbase.Knowledge.FaqEntry
  alias Sanbase.MCP.Knowledge.CreateFaqDraftTool
  alias Sanbase.MCP.Knowledge.Format
  alias Sanbase.MCP.ToolError

  def name(), do: "update_faq_draft"

  @impl true
  def annotations() do
    %{
      "title" => "Update FAQ Draft",
      "readOnlyHint" => false,
      "destructiveHint" => false,
      "idempotentHint" => true,
      "openWorldHint" => false
    }
  end

  schema do
    field(:id, :string, required: true, description: "The draft's id.")
    field(:question, :string, required: false, description: "New question text.")
    field(:answer_markdown, :string, required: false, description: "New Markdown answer.")

    field(:tags, {:list, :string},
      required: false,
      description: "New tag list, any of #{inspect(FaqEntry.allowed_tags())}."
    )

    field(:source_url, :string, required: false, description: "New http(s) source link.")

    field(:internal_notes, :string,
      required: false,
      description: "New reviewer notes; this replaces the previous notes."
    )
  end

  @impl true
  def execute(%{id: id} = params, frame) do
    {:reply, params |> update() |> to_response(id), frame}
  end

  defp update(%{id: id} = params) do
    attrs = Format.draft_attrs(params)

    with :ok <- CreateFaqDraftTool.validate_tags(attrs[:tags]),
         {:ok, entry} <- get_entry(id),
         {:ok, entry} <- Faq.update_draft(entry, attrs) do
      {:ok, Sanbase.Repo.preload(entry, [:tags, :created_by], force: true)}
    end
  end

  defp to_response({:ok, entry}, _id) do
    Response.json(Response.tool(), %{updated: true, entry: Format.faq_entry(entry)})
  end

  defp to_response({:error, :not_a_draft}, id) do
    Format.error_response(
      ToolError.permanent(
        "Entry #{id} is already published and can only be changed in the admin panel: " <>
          Sanbase.Knowledge.Context.faq_admin_url(id)
      )
    )
  end

  defp to_response({:error, :embedding_failed}, _id) do
    Format.error_response(
      ToolError.transient("Could not save the draft right now. Retry shortly.")
    )
  end

  defp to_response({:error, reason}, _id), do: Format.error_response(reason)

  defp get_entry(id) do
    case Faq.get_entry(id) do
      {:ok, entry} -> {:ok, entry}
      {:error, :not_found} -> {:error, ToolError.permanent("No FAQ draft with id #{inspect(id)}")}
    end
  end
end

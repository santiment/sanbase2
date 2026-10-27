defmodule Sanbase.MCP.Knowledge.UpdateFaqDraftTool do
  @moduledoc """
  Revise an FAQ draft that has not been published yet, e.g. after more input from the team.

  Only the fields you pass are changed; `tags`, when given, replaces the whole tag list.
  Published entries cannot be changed here, only in the admin panel.

  Before calling it, show the user the draft and the change, and ask them to confirm they
  want to update it. A draft created by someone else is not changed on the first call: the
  tool says so and names the author. Tell the user explicitly that the draft is NOT theirs,
  ask again, and only after they confirm call again with `confirm: true`.
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
      "destructiveHint" => true,
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

    field(:confirm, :boolean,
      required: false,
      description:
        "Set to true only after the user confirmed updating a draft created by someone else."
    )
  end

  @impl true
  def execute(%{id: id} = params, frame) do
    {:reply, params |> update(frame.assigns.current_user) |> to_response(id), frame}
  end

  defp update(%{id: id} = params, user) do
    attrs = Format.draft_attrs(params)

    with :ok <- CreateFaqDraftTool.validate_tags(attrs[:tags]),
         {:ok, entry} <- get_entry(id),
         :ok <- check_draft(entry),
         :ok <- check_author(entry, user, params[:confirm] == true),
         {:ok, entry} <- Faq.update_draft(entry, attrs) do
      {:ok, Sanbase.Repo.preload(entry, [:tags, :created_by], force: true)}
    end
  end

  # `Faq.update_draft/2` checks again under a row lock, in case it is published meanwhile.
  defp check_draft(%FaqEntry{status: :draft}), do: :ok
  defp check_draft(_entry), do: {:error, :not_a_draft}

  defp check_author(%FaqEntry{created_by_id: user_id}, %{id: user_id}, _confirmed?), do: :ok
  defp check_author(_entry, _user, true = _confirmed?), do: :ok
  defp check_author(entry, _user, false = _confirmed?), do: {:not_author, entry}

  defp to_response({:ok, entry}, _id) do
    Response.json(Response.tool(), %{updated: true, entry: Format.faq_entry(entry)})
  end

  defp to_response({:not_author, entry}, _id) do
    author = (entry.created_by && entry.created_by.email) || "an unknown user"

    Response.json(Response.tool(), %{
      updated: false,
      message:
        "Nothing was changed. This draft was NOT created by you: it was created by " <>
          "#{author}. Tell the user explicitly that it is not their draft and ask them to " <>
          "confirm they want to change it. Only after they confirm, call again with `confirm: true`.",
      entry: Format.faq_entry(entry)
    })
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

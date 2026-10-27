defmodule Sanbase.MCP.Knowledge.Format do
  @moduledoc """
  Shapes knowledge-base records into the JSON the knowledge MCP tools return.

  Every record carries a `type` and an `id`, which is exactly what
  `fetch_entry` takes, so the client can always go from an excerpt to the
  full document. Links come from `Sanbase.Knowledge.Context`, the same place
  the Ask answers build their citations from.
  """

  alias Anubis.Server.Response
  alias Sanbase.Insight.PostEmbedding
  alias Sanbase.Knowledge.Context
  alias Sanbase.Knowledge.FaqEntry

  @doc "A numbered search hit of `source`, as returned by `search_knowledge`."
  @spec hit(map(), Context.source()) :: map()
  def hit(hit, :faq) do
    %{
      n: hit.marker_id,
      type: "faq",
      id: hit.id,
      title: hit.question,
      url: Context.marker(hit, :faq).url,
      similarity: round_similarity(hit[:similarity]),
      # FAQ entries are short and embedded whole, so the hit is the full entry.
      is_full_text: true,
      text: hit.answer_markdown
    }
  end

  def hit(hit, :insight) do
    %{
      n: hit.marker_id,
      type: "insight",
      id: hit.post_id,
      title: hit.post_title,
      url: Context.marker(hit, :insight).url,
      similarity: round_similarity(hit[:similarity]),
      published_on: format_date(hit[:published_at]),
      paywalled: hit[:is_paywall_required] == true,
      is_full_text: false,
      text: PostEmbedding.chunk_body(hit.text_chunk)
    }
  end

  def hit(hit, :academy) do
    %{
      n: hit.marker_id,
      type: "academy",
      id: hit.article_id,
      title: hit.title,
      url: Context.marker(hit, :academy).url,
      similarity: round_similarity(hit[:similarity]),
      section: hit[:heading],
      is_full_text: false,
      text: hit.chunk
    }
  end

  @doc "A full FAQ entry, drafts included, as returned by the FAQ tools."
  @spec faq_entry(%FaqEntry{}) :: map()
  def faq_entry(%FaqEntry{} = entry) do
    %{
      type: "faq",
      id: entry.id,
      status: to_string(entry.status),
      question: entry.question,
      answer_markdown: entry.answer_markdown,
      tags: tag_names(entry.tags),
      source_url: entry.source_url,
      internal_notes: entry.internal_notes,
      created_by: user_email(entry.created_by),
      admin_url: Context.faq_admin_url(entry.id),
      updated_at: format_datetime(entry.updated_at)
    }
  end

  @doc "A similar FAQ entry from `Sanbase.Knowledge.Faq.find_most_similar_faqs/3`."
  @spec similar_faq(map()) :: map()
  def similar_faq(entry) do
    %{
      type: "faq",
      id: entry.id,
      status: to_string(entry.status),
      similarity: round_similarity(entry.similarity),
      question: entry.question,
      answer_markdown: entry.answer_markdown,
      admin_url: Context.faq_admin_url(entry.id)
    }
  end

  @doc "A tool error response for a changeset or an already formatted message."
  @spec error_response(Ecto.Changeset.t() | String.t()) :: Response.t()
  def error_response(%Ecto.Changeset{} = changeset) do
    errors = Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)
    error_response(Sanbase.MCP.ToolError.permanent("Invalid draft: #{errors}"))
  end

  def error_response(message) when is_binary(message) do
    Response.error(Response.tool(), message)
  end

  @doc """
  The FAQ fields a draft tool was given, without the ones left out. Shared by
  `create_faq_draft` and `update_faq_draft`.
  """
  @spec draft_attrs(map()) :: map()
  def draft_attrs(params) do
    params
    |> Map.take([:question, :answer_markdown, :tags, :source_url, :internal_notes])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @spec format_date(term()) :: String.t() | nil
  def format_date(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_date() |> Date.to_iso8601()
  def format_date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_iso8601()
  def format_date(_), do: nil

  defp format_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_datetime(_), do: nil

  defp round_similarity(similarity) when is_float(similarity), do: Float.round(similarity, 3)
  defp round_similarity(_), do: nil

  defp tag_names(tags) when is_list(tags), do: Enum.map(tags, & &1.name)
  defp tag_names(_), do: []

  defp user_email(%Sanbase.Accounts.User{email: email}), do: email
  defp user_email(_), do: nil
end

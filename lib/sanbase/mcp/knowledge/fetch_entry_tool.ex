defmodule Sanbase.MCP.Knowledge.FetchEntryTool do
  @moduledoc """
  Fetch the full text of one knowledge-base document by the `type` and `id` from a
  `search_knowledge` excerpt.

  Use it when an excerpt (`is_full_text: false`) is cut short and the answer needs the rest of
  the Academy article or Insight, or to reread an FAQ entry or draft by its id.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.Insight.Post
  alias Sanbase.Knowledge.Academy
  alias Sanbase.Knowledge.Faq
  alias Sanbase.MCP.Knowledge.Format
  alias Sanbase.MCP.ToolError

  @max_text_length 40_000

  def name(), do: "fetch_entry"

  @impl true
  def annotations() do
    %{
      "title" => "Fetch Knowledge Entry",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:type, :enum,
      type: :string,
      values: ~w(faq academy insight),
      required: true,
      description: "The `type` of the excerpt: faq, academy or insight."
    )

    field(:id, {:either, {:string, :integer}},
      required: true,
      description: "The `id` of the excerpt (a UUID for faq, an integer for academy and insight)."
    )
  end

  @impl true
  def execute(%{type: type, id: id}, frame) do
    case fetch(type, id) do
      {:ok, entry} ->
        {:reply, Response.json(Response.tool(), entry), frame}

      {:error, :not_found} ->
        message =
          ToolError.permanent(
            "No #{type} entry with id #{inspect(id)}. Use an id from `search_knowledge`."
          )

        {:reply, Response.error(Response.tool(), message), frame}
    end
  end

  defp fetch("faq", id) do
    with {:ok, entry} <- Faq.get_entry(to_string(id)) do
      {:ok, Format.faq_entry(entry)}
    end
  end

  defp fetch("academy", id) do
    with {:ok, article_id} <- parse_integer(id),
         {:ok, article} <- Academy.get_article_with_text(article_id) do
      {:ok, Map.merge(%{type: "academy"}, article)}
    end
  end

  defp fetch("insight", id) do
    with {:ok, post_id} <- parse_integer(id),
         {:ok, post} <- Post.by_id(post_id, []),
         true <- visible?(post) do
      post = Sanbase.Repo.preload(post, [:tags, :user])

      {:ok,
       %{
         type: "insight",
         id: post.id,
         title: post.title,
         url: SanbaseWeb.Endpoint.insight_url(post.id),
         published_on: Format.format_date(post.published_at),
         author: post.user && post.user.username,
         tags: Enum.map(post.tags, & &1.name),
         paywalled: post.is_paywall_required == true,
         text: truncate(post.text)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch(_type, _id), do: {:error, :not_found}

  defp visible?(%Post{} = post) do
    post.ready_state == Post.published() and post.state == Post.approved_state() and
      post.is_deleted != true
  end

  defp parse_integer(id) when is_integer(id), do: {:ok, id}

  defp parse_integer(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :not_found}
    end
  end

  defp parse_integer(_), do: {:error, :not_found}

  defp truncate(nil), do: nil

  defp truncate(text) do
    if String.length(text) <= @max_text_length do
      text
    else
      String.slice(text, 0, @max_text_length) <> "\n\n[… truncated]"
    end
  end
end

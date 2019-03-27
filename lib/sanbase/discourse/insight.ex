defmodule Sanbase.Discourse.Insight do
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Insight.Post
  alias Sanbase.Discourse

  def create_discourse_topic(%Post{id: id, title: title, inserted_at: inserted_at}) do
    link = posts_url(id)

    text = ~s"""
      This topic hosts the discussion about [#{link}](#{link})
    """

    title = "##{id} | #{title} | #{DateTime.to_naive(inserted_at) |> to_string}"

    Discourse.Api.publish(title, text)
    |> case do
      {:ok,
       %{
         "topic_id" => topic_id,
         "topic_slug" => topic_slug
       }} ->
        {:ok, discourse_topic_url(topic_id, topic_slug)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp discourse_topic_url(topic_id, topic_slug) do
    discourse_url()
    |> URI.parse()
    |> URI.merge("/t/#{topic_slug}/#{topic_id}")
    |> URI.to_string()
  end

  defp posts_url(id), do: "#{sanbase_url()}/insights/read/#{id}"
  defp sanbase_url(), do: Config.module_get(SanbaseWeb.Endpoint, :frontend_url)
  defp discourse_url(), do: Config.module_get(Sanbase.Discourse, :url)
end

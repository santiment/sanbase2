defmodule Sanbase.Discourse.Insight do
  require Sanbase.Utils.Config, as: Config
  require Mockery.Macro

  alias Sanbase.Insight.Post
  alias Sanbase.Notifications

  def create_discourse_topic(%Post{id: id, title: title, inserted_at: inserted_at} = post) do
    link = posts_url(id)

    text = ~s"""
      This topic hosts the discussion about [#{link}](#{link})
    """

    title = "##{id} | #{title} | #{DateTime.to_naive(inserted_at) |> to_string}"

    {:ok,
     %{
       "topic_id" => topic_id,
       "topic_slug" => topic_slug
     }} = discourse_api().publish(title, text)

    discourse_topic_url =
      discourse_url()
      |> URI.parse()
      |> URI.merge("/t/#{topic_slug}/#{topic_id}")
      |> URI.to_string()

    {:ok, discourse_topic_url}
  end

  defp posts_url(id), do: "#{sanbase_url()}/insights/read/#{id}"
  defp sanbase_url(), do: Config.module_get(SanbaseWeb.Endpoint, :frontend_url)
  defp discourse_url(), do: Config.module_get(Sanbase.Discourse, :url)
  defp discourse_api(), do: Mockery.Macro.mockable(Sanbase.Discourse.Api)
end

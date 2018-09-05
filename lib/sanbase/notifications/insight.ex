defmodule Sanbase.Notifications.Insight do
  require Mockery.Macro
  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Voting.Post

  def publish_in_discord(post) do
    post
    |> new_insight_discord_content()
    |> create_discord_payload()
    |> publish()
    |> case do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        :ok

      {:error, error} ->
        Logger.error("Cannot publish insight [#{post.id}] in discord" <> inspect(error))
    end
  end

  defp new_insight_discord_content(%Post{id: id, title: title} = _post) do
    link = posts_url(id)

    ~s"""
    New insight published: #{title} [#{link}]
    """
  end

  defp publish(payload) do
    http_client().post(discord_webhook_url(), payload, [{"Content-Type", "application/json"}])
  end

  defp create_discord_payload(content) do
    Poison.encode!(%{content: content, username: insights_discord_publish_user()})
  end

  defp discord_webhook_url do
    Config.get(:webhook_url)
  end

  defp insights_discord_publish_user do
    Config.get(:insights_discord_publish_user)
  end

  defp posts_url(id), do: "#{sanbase_url()}/insights/#{id}"
  defp sanbase_url(), do: Config.module_get(SanbaseWeb.Endpoint, :frontend_url)
  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)
end

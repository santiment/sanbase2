defmodule Sanbase.Notifications.Insight do
  require Mockery.Macro
  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Voting.Post

  def publish_in_discord(post) do
    post
    |> create_discord_payload()
    |> publish()
    |> case do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("Cannot publish insight [#{post.id}] in discord: code[#{status_code}]")

      {:error, error} ->
        Logger.error("Cannot publish insight [#{post.id}] in discord: " <> inspect(error))
    end
  end

  defp create_discord_payload(%Post{id: id, title: title} = _post) do
    link = posts_url(id)

    content = ~s"""
    New insight published: #{title} [#{link}]
    """

    Poison.encode!(%{content: content, username: insights_discord_publish_user()})
  end

  defp publish(payload) do
    http_client().post(discord_webhook_url(), payload, [{"Content-Type", "application/json"}])
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

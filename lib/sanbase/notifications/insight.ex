defmodule Sanbase.Notifications.Insight do
  require Mockery.Macro
  alias Sanbase.Utils.Config
  require Logger

  alias Sanbase.Insight.Post

  def publish_in_discord(post) do
    case Config.module_get(__MODULE__, :enabled, "true") |> String.to_existing_atom() do
      true -> do_publish_in_discord(post)
      false -> :ok
    end
  end

  def do_publish_in_discord(post) do
    post
    |> create_discord_payload()
    |> publish()
    |> case do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("Can't publish insight [#{post.id}] in discord: code[#{status_code}]")
        {:error, "Can't publish insight creation notification to Discord"}

      {:error, error} ->
        Logger.error("Cannot publish insight [#{post.id}] in discord: " <> inspect(error))
        {:error, "Can't publish insight creation notification to Discord"}
    end
  end

  defp create_discord_payload(
         %Post{id: id, title: title, user: user, published_at: published_at} = _post
       ) do
    link = posts_url(id)

    content = ~s"""
    New insight posted:
    Title: #{title}
    Author: #{user.username || "anonymous"}
    Link: #{link}
    Published at: #{Timex.format!(published_at, "%F %T%:z", :strftime)}
    """

    Jason.encode!(%{content: content, username: insights_discord_publish_user()})
  end

  defp publish(payload) do
    http_client().post(discord_webhook_url(), payload, [{"Content-Type", "application/json"}])
  end

  defp discord_webhook_url do
    Config.module_get(__MODULE__, :webhook_url)
  end

  defp insights_discord_publish_user do
    Config.module_get(__MODULE__, :insights_discord_publish_user)
  end

  defp posts_url(id), do: "#{insights_url()}/read/#{id}"
  defp insights_url(), do: Config.module_get(SanbaseWeb.Endpoint, :insights_url)
  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)
end

defmodule Sanbase.Notifications.Insight do
  require Mockery.Macro
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Notifications.PriceVolumeDiff

  def publish_discord(content) do
    payload = create_discord_payload(content)

    http_client().post(discord_webhook_url(), payload, [{"Content-Type", "application/json"}])
  end

  defp create_discord_payload(content) do
    Poison.encode!(%{content: content, username: insights_discord_publish_user()})
  end

  defp discord_webhook_url do
    Config.module_get(PriceVolumeDiff, :webhook_url)
  end

  defp insights_discord_publish_user do
    Config.get(:insights_discord_publish_user)
  end

  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)
end

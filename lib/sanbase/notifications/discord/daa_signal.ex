defmodule Sanbase.Notifications.Discord.DaaSignal do
  @moduledoc ~s"""
  Send a notification when there is a spike in Daily Active Addresses
  """

  @behaviour Sanbase.Notifications.Behaviour

  require Mockery.Macro
  require Sanbase.Utils.Config, as: Config
  require Logger

  import Ecto.Query, only: [from: 2]

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Blockchain.DailyActiveAddresses

  alias Sanbase.Notifications.Discord

  @impl true
  def run() do
    projects_to_signal =
      all_projects()
      |> Project.projects_over_volume_threshold(config_threshold())
      |> Enum.map(&check_for_project/1)
      |> Enum.reject(&is_nil/1)

    if Enum.count(projects_to_signal) > 0 do
      projects_to_signal
      |> Enum.map(&create_notification_content/1)
      |> Enum.each(fn {payload, embeded_image} ->
        payload
        |> encode!(config_publish_user(), embeded_image)
        |> publish("discord")
      end)
    else
      Logger.info("DAA Signal finished with nothing to publish")
      :ok
    end
  end

  @impl true
  def publish(payload, "discord") do
    Logger.info("Sending Discord notification for Daily Active Addresses: #{payload}")
    Discord.send_notification(config_webhook_url(), "DAA Signal", payload)
  end

  # Private functions

  defp encode!(payload, publish_user, embeds) do
    Jason.encode!(%{content: payload, username: publish_user, embeds: embeds})
  end

  def build_embeded_url(slug, from, to) do
    url = Discord.build_candlestick_image_url(slug, from, to)
    [%{image: %{url: url}}]
  end

  defp all_projects() do
    from(
      p in Project,
      where: not is_nil(p.coinmarketcap_id) and not is_nil(p.main_contract_address)
    )
    |> Repo.all()
  end

  defp check_for_project(project) do
    {:ok, base_daa} =
      project.main_contract_address
      |> DailyActiveAddresses.active_addresses(timeframe_from(), timeframe_to())

    {:ok, new_daa} =
      project.main_contract_address
      |> DailyActiveAddresses.active_addresses(two_days_ago(), one_day_ago())

    Logger.info(
      "DAA signal check: #{project.coinmarketcap_id}, #{base_daa}, #{new_daa}, #{
        new_daa > config_change() * base_daa
      }"
    )

    if new_daa > config_change() * base_daa do
      {project.name, project.coinmarketcap_id, base_daa, new_daa}
    else
      nil
    end
  end

  defp create_notification_content({project_name, project_slug, base_daa, new_daa}) do
    content = """
    #{project_name}: Daily Active Addresses has gone up by #{percent_change(new_daa, base_daa)}% : #{
      notification_emoji_up()
    }.
    DAA for yesterday: #{new_daa}, Average DAA for last #{config_timeframe_from()} days: #{
      base_daa
    }.
    More info here: #{project_page(project_slug)}
    """

    url = build_embeded_url(project_slug, timeframe_from(), timeframe_to())

    {content, url}
  end

  defp notification_emoji_up() do
    ":small_red_triangle:"
  end

  defp percent_change(new_daa, base_daa) do
    Float.round(new_daa / base_daa * 100)
  end

  defp project_page(coinmarketcap_id) do
    "https://app.santiment.net" <> "/projects/" <> coinmarketcap_id
  end

  defp config_webhook_url() do
    Config.get(:webhook_url)
  end

  defp config_publish_user() do
    Config.get(:publish_user)
  end

  defp config_timeframe_from() do
    Config.get(:timeframe_from) |> String.to_integer()
  end

  defp config_timeframe_to() do
    Config.get(:timeframe_to) |> String.to_integer()
  end

  defp config_change() do
    Config.get(:change) |> String.to_integer()
  end

  defp config_threshold() do
    Config.get(:trading_volume_threshold) |> String.to_integer()
  end

  defp one_day_ago(), do: Timex.shift(Timex.now(), days: -1)
  defp two_days_ago(), do: Timex.shift(Timex.now(), days: -2)
  defp timeframe_from(), do: Timex.shift(Timex.now(), days: -1 * config_timeframe_from())
  defp timeframe_to(), do: Timex.shift(Timex.now(), days: -1 * config_timeframe_to())
end

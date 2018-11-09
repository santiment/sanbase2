defmodule Sanbase.Notifications.Discord.DaaSignal do
  require Mockery.Macro
  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Blockchain.DailyActiveAddresses

  def run() do
    payload = create_daa_signal_payload()

    if payload do
      Logger.info("DaaSignal check finished. Content to publish: #{payload}")

      payload
      |> publish_in_discord()
      |> check_discord_response()
    else
      Logger.info("DaaSignal finished with nothing to publish")
      :ok
    end
  end

  defp check_discord_response(response) do
    case response do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("Cannot publish DAA signal in discord: code[#{status_code}]")
        {:error, "Cannot publish DAA signal in discord"}

      {:error, error} ->
        Logger.error("Cannot publish DAA signal in discord " <> inspect(error))
        {:error, "Cannot publish DAA signal in discord"}
    end
  end

  defp create_daa_signal_payload() do
    projects_to_signal =
      all_projects()
      |> Enum.map(&check_for_project/1)
      |> Enum.reject(&is_nil/1)

    if Enum.count(projects_to_signal) > 0 do
      content =
        projects_to_signal
        |> Enum.map(&create_notification_content/1)
        |> Enum.join("\n")

      Jason.encode!(%{content: content, username: config_publish_user()})
    else
      nil
    end
  end

  defp create_notification_content({project_name, project_slug, base_daa, new_daa}) do
    """
    #{project_name}: Daily Active Addresses has gone up by #{percent_change(new_daa, base_daa)}% : #{
      notification_emoji_up()
    }.
    DAA for yesterday: #{new_daa}, Average DAA for last #{config_timeframe_from()} days: #{
      base_daa
    }.
    More info here: #{project_page(project_slug)}
    """
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

  defp all_projects() do
    Project
    |> Repo.all()
    |> Enum.filter(fn p -> p.main_contract_address && p.coinmarketcap_id end)
  end

  defp publish_in_discord(payload) do
    http_client().post(config_webhook_url(), payload, [{"Content-Type", "application/json"}])
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
    Config.get(:threshold) |> String.to_integer()
  end

  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)
  def one_day_ago(), do: Timex.shift(Timex.now(), days: -1)
  def two_days_ago(), do: Timex.shift(Timex.now(), days: -2)
  def timeframe_from(), do: Timex.shift(Timex.now(), days: -1 * config_timeframe_from())
  def timeframe_to(), do: Timex.shift(Timex.now(), days: -1 * config_timeframe_to())
end

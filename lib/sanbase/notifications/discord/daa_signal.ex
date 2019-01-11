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
  alias Sanbase.Clickhouse.Erc20DailyActiveAddresses

  alias Sanbase.Notifications.{Discord, Notification, Type}

  @impl true
  def run() do
    projects = projects_over_threshold()

    avg_daa_for_projects = get_or_store_avg_daa(projects)
    today_daa_for_projects = all_projects_daa_for_today(projects)

    notification_type = Type.get_or_create("daa_signal")

    projects_to_signal =
      projects
      |> Enum.map(
        &check_for_project(&1, avg_daa_for_projects, today_daa_for_projects, notification_type)
      )
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn {_, _, _, change, _} -> change end, &>=/2)

    if Enum.count(projects_to_signal) > 0 do
      projects_to_signal
      |> Enum.map(&create_notification_content/1)
      |> Enum.each(fn {project, payload, embeds, current_daa} ->
        payload
        |> Discord.encode!(publish_user(), embeds)
        |> publish("discord")

        Notification.insert_triggered(project, notification_type, "#{current_daa}")
      end)
    else
      Logger.info("DAA Signal finished with nothing to publish")
      :ok
    end
  end

  @impl true
  def publish(payload, "discord") do
    Logger.info("Sending Discord notification for Daily Active Addresses: #{payload}")
    Discord.send_notification(webhook_url(), "DAA Signal", payload)
  end

  # Private functions

  defp all_projects() do
    from(
      p in Project,
      where: not is_nil(p.coinmarketcap_id) and not is_nil(p.main_contract_address)
    )
    |> Repo.all()
  end

  defp projects_over_threshold() do
    all_projects()
    |> Project.projects_over_volume_threshold(threshold())
  end

  defp check_for_project(project, avg_daa_for_projects, today_daa_for_projects, notification_type) do
    if Notification.has_cooldown?(project, notification_type, project_cooldown()) do
      nil
    else
      avg_daa = get_daa_contract(project.main_contract_address, avg_daa_for_projects)
      current_daa = get_daa_contract(project.main_contract_address, today_daa_for_projects)
      {last_triggered_daa, hours} = last_triggered_daa(project, notification_type)

      Logger.info(
        "DAA signal check: #{project.coinmarketcap_id}, #{avg_daa}, #{current_daa}, #{
          last_triggered_daa
        } #{hours},  #{current_daa - last_triggered_daa > threshold_change() * avg_daa}"
      )

      if current_daa - last_triggered_daa > threshold_change() * avg_daa do
        {project, avg_daa, current_daa - last_triggered_daa,
         percent_change(current_daa - last_triggered_daa, avg_daa), hours}
      else
        nil
      end
    end
  end

  defp last_triggered_daa(project, type) do
    now = Timex.now()
    start_of_day = Timex.beginning_of_day(now)
    end_of_day = Timex.end_of_day(now)

    from(n in Notification,
      where:
        n.project_id == ^project.id and n.type_id == ^type.id and n.inserted_at >= ^start_of_day and
          n.inserted_at <= ^end_of_day,
      order_by: [desc: n.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil ->
        {0, diff_in_hours(start_of_day, now)}

      %Notification{data: data} when is_nil(data) ->
        {0, diff_in_hours(start_of_day, now)}

      %Notification{data: data, inserted_at: inserted_at} when is_binary(data) ->
        {String.to_integer(data), diff_in_hours(inserted_at, now)}
    end
  end

  defp create_notification_content({
         %Project{name: project_name} = project,
         avg_daa,
         current_daa,
         percent_change,
         hours
       }) do
    content = """
    `#{project_name}`: Daily Active Addresses has gone up #{notification_emoji_up()} by `#{
      percent_change
    }%` for the last #{hours} hours.

    Daily Active Addresses for last `#{hours} hours` : `#{current_daa}`
    Average Daily Active Addresses for last `#{config_timeframe_from() - 1} days`: `#{avg_daa}`.

    More info here: #{Project.sanbase_link(project)}
    """

    embeds =
      Discord.build_embedded_chart(
        project,
        Timex.shift(Timex.now(), days: -90),
        Timex.now(),
        chart_type: :daily_active_addresses
      )

    {project, content, embeds, current_daa}
  end

  defp get_or_store_avg_daa(projects) do
    ConCache.get_or_store(:signals_cache, "daa_signal_#{today_str()}_averages", fn ->
      projects
      |> Enum.map(& &1.main_contract_address)
      |> Enum.chunk_every(100)
      |> Enum.flat_map(fn contracts ->
        {:ok, daa_result} =
          Erc20DailyActiveAddresses.average_active_addresses(
            contracts,
            timeframe_from(),
            timeframe_to()
          )

        daa_result
      end)
    end)
  end

  defp get_daa_contract(contract, all_projects_daa) do
    all_projects_daa
    |> Map.new()
    |> Map.get(contract, 0)
  end

  defp all_projects_daa_for_today(projects) do
    projects
    |> Enum.map(& &1.main_contract_address)
    |> Enum.chunk_every(100)
    |> Enum.flat_map(fn contracts ->
      {:ok, today_daa} = Erc20DailyActiveAddresses.realtime_active_addresses(contracts)
      today_daa
    end)
  end

  defp diff_in_hours(datetime, last_datetime \\ Timex.now())

  defp diff_in_hours(%NaiveDateTime{} = datetime, last_datetime) do
    Timex.diff(last_datetime, DateTime.from_naive!(datetime, "Etc/UTC"), :hours) |> abs
  end

  defp diff_in_hours(%DateTime{} = datetime, last_datetime) do
    Timex.diff(last_datetime, datetime, :hours) |> abs
  end

  defp today_str() do
    to_string(Timex.to_date(Timex.now()))
  end

  defp notification_emoji_up() do
    ":small_red_triangle:"
  end

  defp percent_change(current_daa, avg_daa) do
    Float.round(current_daa / avg_daa * 100)
  end

  defp webhook_url() do
    Config.get(:webhook_url)
  end

  defp publish_user() do
    Config.get(:publish_user)
  end

  defp threshold_change() do
    Config.get(:change) |> String.to_integer()
  end

  defp threshold() do
    Config.get(:trading_volume_threshold) |> String.to_integer()
  end

  # cooldown for project in seconds
  defp project_cooldown() do
    Config.get(:project_cooldown) |> String.to_integer()
  end

  defp timeframe_from(), do: Timex.shift(Timex.now(), days: -1 * config_timeframe_from())
  defp timeframe_to(), do: Timex.shift(Timex.now(), days: -1 * config_timeframe_to())
  defp config_timeframe_from(), do: Config.get(:timeframe_from) |> String.to_integer()
  defp config_timeframe_to(), do: Config.get(:timeframe_to) |> String.to_integer()
end

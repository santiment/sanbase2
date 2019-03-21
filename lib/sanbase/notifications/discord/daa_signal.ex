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
  alias Sanbase.Clickhouse.DailyActiveAddresses

  alias Sanbase.Notifications.{Discord, Notification, Type}

  @cache_id :signals_cache

  @impl true
  def run() do
    projects = projects_over_threshold()

    with {:ok, avg_daa_for_projects} <- get_or_store_avg_daa(projects),
         {:ok, today_daa_for_projects} <- all_projects_daa_for_today(projects) do
      notification_type = Type.get_or_create("daa_signal")

      projects_to_signal =
        projects_to_signal(
          projects,
          avg_daa_for_projects,
          today_daa_for_projects,
          notification_type
        )

      if Enum.count(projects_to_signal) > 0 do
        send_and_persist(projects_to_signal, notification_type)
      else
        Logger.info("Daily Active Addresses Signal finished with nothing to publish")
        :ok
      end
    else
      {:error, error} ->
        Logger.error(
          "Error while executing Daily Active Addresses Signal. Reason: #{inspect(error)}"
        )
    end
  end

  @impl true
  def publish(payload, "discord") do
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

  defp projects_to_signal(
         projects,
         avg_daa_for_projects,
         today_daa_for_projects,
         notification_type
       ) do
    projects
    |> Enum.map(
      &check_for_project(&1, avg_daa_for_projects, today_daa_for_projects, notification_type)
    )
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_, _, _, _, change, _} -> change end, &>=/2)
  end

  defp send_and_persist(projects_to_signal, notification_type) do
    projects_to_signal
    |> Enum.map(&create_notification_content/1)
    |> Enum.each(fn {project, payload, embeds, current_daa} ->
      payload
      |> Discord.encode!(publish_user(), embeds)
      |> publish("discord")

      Notification.insert_triggered(project, notification_type, "#{current_daa}")
    end)
  end

  defp check_for_project(project, avg_daa_for_projects, today_daa_for_projects, notification_type) do
    if Notification.has_cooldown?(project, notification_type, project_cooldown()) do
      nil
    else
      avg_daa = get_daa_contract(Project.contract_address(project), avg_daa_for_projects)
      current_daa = get_daa_contract(Project.contract_address(project), today_daa_for_projects)
      {last_triggered_daa, hours} = last_triggered_daa(project, notification_type)

      percent_change = percent_change(avg_daa, current_daa - last_triggered_daa)

      Logger.info(
        "DAA signal check: #{project.coinmarketcap_id}, #{avg_daa}, #{current_daa}, #{
          last_triggered_daa
        }, #{percent_change}%, #{hours}, #{percent_change > threshold_change() * 100}"
      )

      if percent_change > threshold_change() * 100 do
        {project, avg_daa, current_daa, last_triggered_daa, percent_change, hours}
      else
        nil
      end
    end
  end

  def last_triggered_daa(project, type) do
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
         last_triggered_daa,
         percent_change,
         hours
       }) do
    content = """
    **#{project_name}** Daily Active Addresses has gone up #{notification_emoji_up()} by **#{
      percent_change
    }%** for the last **#{hours} hour(s)**.
    Daily Active Addresses for last **#{hours} hour(s)** : **#{current_daa - last_triggered_daa}**
    Average Daily Active Addresses for last **#{config_timeframe_from() - 1} days**: **#{avg_daa}**.
    More info here: #{Project.sanbase_link(project)}
    """

    embeds =
      Sanbase.Chart.build_embedded_chart(
        project,
        Timex.shift(Timex.now(), days: -90),
        Timex.now(),
        chart_type: :daily_active_addresses
      )

    {project, content, embeds, current_daa}
  end

  defp get_or_store_avg_daa(projects) do
    cache_key = "daa_signal_#{today_str()}_averages"

    ConCache.get(@cache_id, cache_key)
    |> case do
      nil ->
        get_avg_daa(projects)
        |> case do
          {:ok, avg_daa} ->
            :ok = ConCache.put(@cache_id, cache_key, avg_daa)
            {:ok, avg_daa}

          {:error, error} ->
            {:error, error}
        end

      avg_daa ->
        {:ok, avg_daa}
    end
  end

  defp get_avg_daa(projects) do
    projects
    |> Enum.map(&Project.contract_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(100)
    |> Enum.map(fn contracts ->
      DailyActiveAddresses.average_active_addresses(
        contracts,
        timeframe_from(),
        timeframe_to()
      )
    end)
    |> handle_errors()
  end

  defp get_daa_contract(contract, all_projects_daa) do
    all_projects_daa
    |> Map.new()
    |> Map.get(contract, 0)
  end

  defp all_projects_daa_for_today(projects) do
    projects
    |> Enum.map(&Project.contract_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(100)
    |> Enum.map(fn contracts ->
      DailyActiveAddresses.realtime_active_addresses(contracts)
    end)
    |> handle_errors()
  end

  defp handle_errors(daa_for_projects) do
    daa_for_projects
    |> Enum.find(&match?({:error, _}, &1))
    |> case do
      {:error, error} ->
        {:error, error}

      nil ->
        {
          :ok,
          daa_for_projects
          |> Enum.flat_map(fn {:ok, daa} -> daa end)
        }
    end
  end

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

  defp percent_change(0, _current), do: 0
  defp percent_change(nil, _current), do: 0

  defp percent_change(previous, current) do
    Float.round((current - previous) / previous * 100)
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

defmodule Sanbase.Notifications.Discord.ExchangeInflow do
  @moduledoc ~s"""
  Send a notification when a given % of the total supply of tokens gets
  deposited into exchanges.
  """
  @behaviour Sanbase.Notifications.Behaviour

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project
  alias Sanbase.Metric
  alias Sanbase.Notifications.{Discord, Notification, Type}
  @impl true
  def run() do
    Logger.info("Running ExchangeInflow signal")
    volume_threshold = Config.get(:trading_volume_threshold) |> String.to_integer()

    to = DateTime.utc_now()
    from = Timex.shift(to, days: -interval_days())

    projects =
      Project.List.projects()
      |> Project.projects_over_volume_threshold(volume_threshold)
      |> Enum.map(fn project ->
        # Downcase the contract address and transform it to "ETH" in case of Ethereum
        %Project{project | main_contract_address: Project.contract_address(project)}
      end)

    slugs = Enum.map(projects, & &1.slug) |> Enum.reject(&is_nil/1)

    Metric.aggregated_timeseries_data("exchange_inflow", slugs, from, to, :sum)
    |> case do
      {:ok, list} ->
        notification_type = Type.get_or_create("exchange_inflow")

        case build_payload(projects, list) do
          [] ->
            Logger.info(
              "There are no signals for tokens moved into exchanges. Won't send anything to Discord."
            )

          payloads ->
            payloads
            |> Enum.each(fn {project, payload, embeds, _percent_change} ->
              payload
              |> Discord.encode!(publish_user(), embeds)
              |> publish("discord")

              Notification.set_triggered(project, notification_type)
            end)
        end
    end
  end

  @impl true
  def publish(payload, "discord") do
    Logger.info("Sending Discord notification for ExchangeInflow...")

    if payload do
      Discord.send_notification(webhook_url(), "Exchange Inflow", payload)
    end
  end

  # Private functions

  defp build_payload(projects, list) do
    slug_inflow_map =
      Enum.map(list, fn %{slug: slug, value: inflow} -> {slug, inflow} end)
      |> Map.new()

    notification_type = Type.get_or_create("exchange_inflow")

    projects
    |> Enum.map(fn %Project{slug: slug} = project ->
      inflow = Map.get(slug_inflow_map, slug)

      build_project_payload(project, notification_type, inflow)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_, _, _, percent_change} -> percent_change end, &Kernel.>=/2)
  end

  defp percent_of_total_supply(_, nil), do: nil

  defp percent_of_total_supply(
         %Project{} = project,
         inflow
       ) do
    tokens_amount = Project.supply(project)
    percent = inflow / tokens_amount * 100
    percent |> Float.round(3)
  end

  defp build_project_payload(_, _, nil), do: nil

  defp build_project_payload(%Project{} = project, notification_type, inflow) do
    percent_of_total_supply = percent_of_total_supply(project, inflow)

    if percent_of_total_supply > signal_trigger_percent(project) do
      # If there was a signal less than interval_days() ago then recalculate the exchange inflow
      # since the last signal trigger time
      case Notification.get_cooldown(project, notification_type, cooldown_days() * 86_400) do
        {true, %DateTime{} = cooldown} ->
          build_payload(project, cooldown, inflow)

        {false, _} ->
          content = notification_message(project, interval_days(), :day, inflow)
          embeds = notification_embeds(project)
          {project, content, embeds, percent_of_total_supply}
      end
    end
  end

  defp build_payload(%Project{} = project, from, inflow) do
    %Project{slug: slug} = project

    case Metric.aggregated_timeseries_data("exchange_inflow", slug, from, Timex.now(), :sum) do
      {:ok, [%{slug: ^slug, value: new_inflow}]} ->
        new_percent_of_total_supply = percent_of_total_supply(project, new_inflow)

        if new_inflow && new_percent_of_total_supply > signal_trigger_percent(project) do
          content =
            notification_message(
              project,
              Timex.diff(from, Timex.now(), :hours) |> abs(),
              :hour,
              inflow,
              new_inflow
            )

          embeds = notification_embeds(project)
          {project, content, embeds, new_percent_of_total_supply}
        end

      _ ->
        nil
    end
  end

  defp notification_message(project, timespan, timespan_format, inflow) do
    {:ok, {avg_price_usd, _avg_price_btc}} =
      Sanbase.Prices.Store.fetch_average_price(
        Sanbase.Influxdb.Measurement.name_from(project),
        Timex.shift(Timex.now(), days: -interval_days()),
        Timex.now()
      )

    """
    Project **#{project.name}** has **#{percent_of_total_supply(project, inflow)}%** of its circulating supply (#{
      inflow |> Number.Delimit.number_to_delimited(precision: 0)
    } out of #{Project.supply(project) |> Number.Delimit.number_to_delimited(precision: 0)} tokens) deposited into exchanges in the past #{
      timespan
    } #{timespan_format}(s).
    The approximate USD value of the moved tokens is $#{
      Number.Delimit.number_to_delimited(inflow * avg_price_usd)
    }
    #{Project.sanbase_link(project)}
    """
  end

  defp notification_message(project, timespan, timespan_format, inflow, cooldown_inflow) do
    {:ok, {avg_price_usd, _avg_price_btc}} =
      Sanbase.Prices.Store.fetch_average_price(
        Sanbase.Influxdb.Measurement.name_from(project),
        Timex.shift(Timex.now(), days: -interval_days()),
        Timex.now()
      )

    """
    Project **#{project.name}** has **#{percent_of_total_supply(project, cooldown_inflow)}%** of its circulating supply (#{
      cooldown_inflow |> Number.Delimit.number_to_delimited(precision: 0)
    } out of #{Project.supply(project) |> Number.Delimit.number_to_delimited(precision: 0)} tokens) deposited into exchanges in the past #{
      timespan
    } #{timespan_format}(s).
    The approximate USD value of the moved tokens is $#{
      Number.Delimit.number_to_delimited(cooldown_inflow * avg_price_usd)
    }

    In total #{percent_of_total_supply(project, inflow)}% (#{
      inflow |> Number.Delimit.number_to_delimited(precision: 0)
    } tokens) were deposited into exchanges in the past #{interval_days()} day(s).
    The approximate USD value of total tokens moved is $#{
      Number.Delimit.number_to_delimited(inflow * avg_price_usd)
    }
    #{Project.sanbase_link(project)}
    """
  end

  defp notification_embeds(project) do
    Sanbase.Chart.build_embedded_chart(
      project,
      Timex.shift(Timex.now(), days: -90),
      Timex.now(),
      chart_type: {:metric, "exchange_inflow"}
    )
  end

  defp signal_trigger_percent(%Project{slug: "ethereum"}) do
    {trigger, ""} = Config.get(:ethereum_signal_trigger_percent) |> Float.parse()
    trigger
  end

  defp signal_trigger_percent(_) do
    {trigger, ""} = Config.get(:signal_trigger_percent) |> Float.parse()
    trigger
  end

  defp interval_days(), do: Config.get(:interval_days) |> String.to_integer()

  defp cooldown_days(), do: Config.get(:cooldown_days) |> String.to_integer()

  defp webhook_url(), do: Config.get(:webhook_url)

  defp publish_user(), do: Config.get(:publish_user)
end

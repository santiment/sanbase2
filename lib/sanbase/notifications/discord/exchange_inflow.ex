defmodule Sanbase.Notifications.Discord.ExchangeInflow do
  @moduledoc ~s"""
  Send a notification when a given % of the total supply of tokens gets
  deposited into exchanges.
  """
  @behaviour Sanbase.Notifications.Behaviour

  require Logger
  require Sanbase.Utils.Config, as: Config
  require Mockery.Macro

  import Ecto.Query

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Notifications.{Discord, Notification, Type}

  @impl true
  def run() do
    Logger.info("Running ExchangeInflow signal")
    volume_threshold = Config.get(:trading_volume_threshold) |> String.to_integer()

    to = DateTime.utc_now()
    from = Timex.shift(to, days: -interval_days())

    projects =
      projects()
      |> Project.projects_over_volume_threshold(volume_threshold)

    projects
    |> Enum.map(& &1.main_contract_address)
    |> Sanbase.Blockchain.ExchangeFundsFlow.transactions_in(from, to)
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

  # Return all projects where the fields that will be used in the signal are not nil
  defp projects() do
    from(
      p in Project,
      preload: [:latest_coinmarketcap_data],
      where:
        not is_nil(p.coinmarketcap_id) and not is_nil(p.main_contract_address) and
          not is_nil(p.token_decimals) and not is_nil(p.name)
    )
    |> Repo.all()
    |> Enum.reject(fn %Project{} = project -> !supply(project) end)
  end

  defp build_payload(projects, list) do
    contract_inflow_map =
      Enum.map(list, fn %{contract: contract, inflow: inflow} -> {contract, inflow} end)
      |> Map.new()

    notification_type = Type.get_or_create("exchange_inflow")

    projects
    |> Enum.map(fn %Project{} = project ->
      inflow = Map.get(contract_inflow_map, project.main_contract_address)

      build_project_payload(project, notification_type, inflow)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_, _, _, percent_change} -> percent_change end, &Kernel.>=/2)
  end

  defp percent_of_total_supply(_, nil), do: nil

  defp percent_of_total_supply(
         %Project{token_decimals: token_decimals} = project,
         inflow
       ) do
    tokens_amount = supply(project) |> Decimal.to_float()
    inflow = inflow / :math.pow(10, token_decimals)
    percent = inflow / tokens_amount * 100
    percent |> Float.round(3)
  end

  defp build_project_payload(_, _, nil), do: nil

  defp build_project_payload(%Project{} = project, notification_type, inflow) do
    percent_of_total_supply = percent_of_total_supply(project, inflow)

    if percent_of_total_supply > signal_trigger_percent() do
      # If there was a signal less than interval_days() ago then recalculate the exchange inflow
      # since the last signal trigger time
      case Notification.get_cooldown(
             project,
             notification_type,
             interval_days() * 86_400
           ) do
        {true, %DateTime{} = cooldown} ->
          with {:ok, [%{inflow: new_inflow}]} <-
                 Sanbase.Blockchain.ExchangeFundsFlow.transactions_in(
                   [project.main_contract_address],
                   cooldown,
                   Timex.now()
                 ) do
            new_percent_of_total_supply = percent_of_total_supply(project, new_inflow)

            if new_inflow && new_percent_of_total_supply > signal_trigger_percent() do
              content =
                notification_message(
                  project,
                  Timex.diff(cooldown, Timex.now(), :hours) |> abs(),
                  :hour,
                  inflow,
                  new_inflow
                )

              embeds = notification_embeds(project)
              {project, content, embeds, new_percent_of_total_supply}
            end
          else
            _ ->
              nil
          end

        {false, _} ->
          content = notification_message(project, interval_days(), :day, inflow)
          embeds = notification_embeds(project)
          {project, content, embeds, percent_of_total_supply}
      end
    end
  end

  defp notification_message(project, timespan, timespan_format, inflow) do
    {:ok, {avg_price_usd, _avg_price_btc}} =
      Sanbase.Prices.Store.fetch_average_price(
        Sanbase.Influxdb.Measurement.name_from(project),
        Timex.shift(Timex.now(), days: -interval_days()),
        Timex.now()
      )

    normalized_inflow = inflow / :math.pow(10, project.token_decimals)

    """
    Project **#{project.name}** has **#{percent_of_total_supply(project, inflow)}%** of its circulating supply (#{
      normalized_inflow |> Number.Delimit.number_to_delimited(precision: 0)
    } out of #{supply(project) |> Number.Delimit.number_to_delimited(precision: 0)} tokens) deposited into exchanges in the past #{
      timespan
    } #{timespan_format}(s).
    The approximate USD value of the moved tokens is $#{
      Number.Delimit.number_to_delimited(normalized_inflow * avg_price_usd)
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

    normalized_inflow = inflow / :math.pow(10, project.token_decimals)
    normalized_cooldown_inflow = cooldown_inflow / :math.pow(10, project.token_decimals)

    """
    Project **#{project.name}** has **#{percent_of_total_supply(project, cooldown_inflow)}%** of its circulating supply (#{
      normalized_cooldown_inflow |> Number.Delimit.number_to_delimited(precision: 0)
    } out of #{supply(project) |> Number.Delimit.number_to_delimited(precision: 0)} tokens) deposited into exchanges in the past #{
      timespan
    } #{timespan_format}(s).
    The approximate USD value of the moved tokens is $#{
      Number.Delimit.number_to_delimited(normalized_cooldown_inflow * avg_price_usd)
    }

    In total #{percent_of_total_supply(project, inflow)}% (#{
      normalized_inflow |> Number.Delimit.number_to_delimited(precision: 0)
    } tokens) were deposited into exchanges in the past #{interval_days()} day(s).
    The approximate USD value of total tokens moved is $#{
      Number.Delimit.number_to_delimited(normalized_inflow * avg_price_usd)
    }
    #{Project.sanbase_link(project)}
    """
  end

  defp notification_embeds(project) do
    Discord.build_embedded_chart(
      project.coinmarketcap_id,
      Timex.shift(Timex.now(), days: -90),
      Timex.now(),
      chart_type: :exchange_inflow
    )
  end

  defp signal_trigger_percent(),
    do: Config.get(:signal_trigger_percent) |> String.to_integer()

  defp interval_days(), do: Config.get(:interval_days) |> String.to_integer()

  defp webhook_url(), do: Config.get(:webhook_url)

  defp publish_user(), do: Config.get(:publish_user)

  defp supply(%Project{total_supply: ts, latest_coinmarketcap_data: nil}), do: ts

  defp supply(%Project{total_supply: ts, latest_coinmarketcap_data: lcd}) do
    lcd.available_supply || lcd.total_supply || ts
  end
end

defmodule Sanbase.Notifications.Discord.ExchangeInflow do
  @moduledoc ~s"""
  Send a notification when a given % of the total supply of tokens gets
  deposited into an exchange.
  """
  @behaviour Sanbase.Notifications.Behaviour

  require Logger
  require Sanbase.Utils.Config, as: Config
  require Mockery.Macro

  import Ecto.Query

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Notifications.Discord
  alias Sanbase.Notifications.Cooldown

  @signal_name "exchange_inflow"

  @impl true
  def run() do
    Logger.info("Running ExchangeInflow signal")
    volume_threshold = Config.get(:trading_volume_threshold) |> String.to_integer()

    from = Timex.shift(Timex.now(), days: -interval_days())
    to = Timex.now()

    projects =
      projects()
      |> Project.projects_over_volume_threshold(volume_threshold)

    projects
    |> Enum.map(& &1.main_contract_address)
    |> Sanbase.Blockchain.ExchangeFundsFlow.transactions_in(from, to)
    |> case do
      {:ok, list} ->
        build_payload(projects, list)
        |> Enum.each(fn {project, payload, embeds} ->
          payload
          |> Discord.encode!(publish_user(), embeds)
          |> publish("discord")

          Cooldown.set_triggered(@signal_name, project.coinmarketcap_id)
        end)

      {:error, error} ->
        Logger.error("Error getting Exchange Inflow from TimescaleDB. Reason: #{inspect(error)}")
        {:error, "Error getting Exchange Inflow from TimescaleDB."}
    end
  end

  @impl true
  def publish(payload, "discord") do
    Logger.info("Sending Discord notification for ExchangeInflow...")

    case payload do
      nil ->
        Logger.info(
          "There are no signals for tokens moved into an exchange. Won't send anything to Discord."
        )

      json_signal ->
        Discord.send_notification(webhook_url(), "Exchange Inflow", json_signal)
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

    projects
    |> Enum.map(fn %Project{} = project ->
      inflow = Map.get(contract_inflow_map, project.main_contract_address)

      build_project_payload(project, inflow)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp percent_of_total_supply(
         %Project{token_decimals: token_decimals} = project,
         inflow
       ) do
    tokens_amount = supply(project) |> Decimal.to_float()
    inflow = inflow / :math.pow(10, token_decimals)
    percent = inflow / tokens_amount * 100
    percent |> Float.round(3)
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

  defp build_project_payload(_, nil), do: nil

  defp build_project_payload(%Project{} = project, inflow) do
    if percent_of_total_supply(project, inflow) > signal_trigger_percent() do
      # If there was a signal less than interval_days() ago then recalculate the exchange inflow
      # since the last signal trigger time
      case Cooldown.get_cooldown(@signal_name, project.coinmarketcap_id, interval_days() * 86_400) do
        {true, %DateTime{} = cooldown} ->
          [%{inflow: new_inflow}] =
            Sanbase.Blockchain.ExchangeFundsFlow.transactions_in(
              [project.main_contract_address],
              cooldown,
              Timex.now()
            )

          if new_inflow && percent_of_total_supply(project, new_inflow) > signal_trigger_percent() do
            message_embeds(project, new_inflow)
          end

        {false, _} ->
          message_embeds(project, inflow)
      end
    end
  end

  defp message_embeds(project, inflow) do
    content = """
    Project #{project.name} has #{percent_of_total_supply(project, inflow)}% of its circulating supply deposited into an exchange in the past #{
      interval_days()
    } day(s).
    In total #{
      (inflow / :math.pow(10, project.token_decimals))
      |> Number.Delimit.number_to_delimited(precision: 0)
    } out of #{supply(project) |> Number.Delimit.number_to_delimited(precision: 0)} tokens were moved into exchanges.
    #{Project.sanbase_link(project)}
    """

    embeds =
      embeds =
      Discord.build_embedded_chart(
        project.coinmarketcap_id,
        Timex.shift(Timex.now(), days: -90),
        Timex.shift(Timex.now(), days: -1),
        chart_type: :exchange_inflow
      )

    {project, content, embeds}
  end
end

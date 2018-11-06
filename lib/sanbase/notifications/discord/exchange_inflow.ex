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

  @impl true
  def run(opts \\ []) do
    projects =
      projects()
      |> filter_projects(opts)

    from = Timex.shift(Timex.now(), days: -interval_days())
    to = Timex.now()

    projects
    |> Enum.map(& &1.main_contract_address)
    |> Sanbase.Blockchain.ExchangeFundsFlow.transactions_in(from, to)
    |> case do
      {:ok, list} ->
        publish("discord", build_payload(projects, list))

      {:error, error} ->
        Logger.error("Error getting Exchange Inflow from TimescaleDB. Reason: #{inspect(error)}")
        {:error, "Error getting Exchange Inflow from TimescaleDB."}
    end
  end

  @impl true
  def publish("discord", payload) do
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
      where:
        not is_nil(p.coinmarketcap_id) and not is_nil(p.main_contract_address) and
          not is_nil(p.token_decimals) and not is_nil(p.total_supply) and not is_nil(p.name)
    )
    |> Repo.all()
  end

  # Return all projects from the list which trading volume is over a given threshold
  defp filter_projects(projects, opts) do
    volume_threshold = Keyword.get(opts, :volume_threshold, 1_000_000)

    measurements_list =
      projects
      |> Enum.map(fn %Project{} = project -> Sanbase.Influxdb.Measurement.name_from(project) end)
      |> Enum.reject(&is_nil/1)

    case measurements_list do
      [] ->
        []

      [_ | _] ->
        measurements_str =
          measurements_list
          |> Enum.map(fn x -> "\"#{x}\"" end)
          |> Enum.join(", ")

        volume_over_threshold_projects =
          Sanbase.Prices.Store.volume_over_threshold(
            measurements_str,
            Timex.shift(Timex.now(), days: -interval_days()),
            Timex.now(),
            volume_threshold
          )

        projects
        |> Enum.filter(fn %Project{} = project ->
          Sanbase.Influxdb.Measurement.name_from(project) in volume_over_threshold_projects
        end)
    end
  end

  defp build_payload(projects, list) do
    contract_inflow_map =
      Enum.map(list, fn %{contract: contract, inflow: inflow} -> {contract, inflow} end)
      |> Map.new()

    projects
    |> Enum.map(fn %Project{} = project ->
      inflow = Map.get(contract_inflow_map, project.main_contract_address)

      if inflow && percent_of_total_supply(project, inflow) > signal_trigger_percent() do
        """
        Project #{project.name} has more than #{signal_trigger_percent()}% of its total supply deposited into an exchange in the past #{
          interval_days()
        } day(s).
        #{Project.sanbase_link(project)}
        """
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Discord.encode!(publish_user())
  end

  defp percent_of_total_supply(
         %Project{total_supply: total_supply, token_decimals: token_decimals},
         inflow
       ) do
    total_supply = Decimal.to_integer(total_supply)
    inflow = inflow / :math.pow(10, token_decimals)
    inflow / total_supply * 100
  end

  defp signal_trigger_percent(),
    do: Config.get(:signal_trigger_percent) |> String.to_integer()

  defp interval_days(), do: Config.get(:interval_days) |> String.to_integer()

  defp webhook_url(), do: Config.get(:webhook_url)

  defp publish_user(), do: Config.get(:publish_user)
end

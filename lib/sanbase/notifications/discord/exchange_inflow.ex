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

  @impl true
  def run(opts \\ []) do
    projects =
      projects()
      |> filter_projects(opts)

    projects
    |> Enum.map(fn %Project{main_contract_address: contract} -> contract end)
    |> Sanbase.Blockchain.ExchangeFundsFlow.transactions_in(
      Timex.shift(Timex.now(), days: -interval_days()),
      Timex.now()
    )
    |> case do
      {:ok, list} ->
        publish("discord", build_payload(projects, list))

      {:error, error} ->
        Logger.error("Error getting exchange inflowfrom TimescaleDB. Reason: #{inspect(error)}")
        з{:error, "Error getting exchange inflowfrom TimescaleDB."}
      end
  end

  @impl true
  def publish("discord", payload) do
    case http_client().post(webhook_url(), payload, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("Cannot publish DAA signal in discord: code[#{status_code}]")

      {:error, error} ->
        Logger.error("Cannot publish DAA signal in discord " <> inspect(error))
    end
  end

  # Private functions

  defp projects() do
    from(
      p in Project,
      where:
        not is_nil(p.coinmarketcap_id) and not is_nil(p.main_contract_address) and
          not is_nil(p.token_decimals) and not is_nil(p.total_supply)
    )
    |> Repo.all()
  end

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
        measurements_str = Enum.join(measurements_list, ", ")

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

      if percent_of_total_supply(project, inflow) > signal_trigger_percent() do
        """
        Project #{project.coinmarketcap_id} (contract address #{project.main_contract_address} has more
        than 1% of its total supply deposited into an exchange in the past #{interval_days()} day(s)
        """
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp percent_of_total_supply(
         %Project{total_supply: total_supply, token_decimals: token_decimals},
         inflow
       ) do
    inflow = inflow / :math.pow(10, token_decimals)
    inflow / total_supply * 100
  end

  defp signal_trigger_percent(),
    do: Config.get(:signal_trigger_percent) |> String.to_integer()

  defp interval_days(), do: Config.get(:interval_days) |> String.to_integer()

  defp webhook_url(), do: Config.get(:webhook_url)

  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)
end

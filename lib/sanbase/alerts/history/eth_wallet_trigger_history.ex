defmodule Sanbase.Alert.History.EthWalletTriggerHistory do
  @moduledoc """
  Implementations of historical trigger points for eth_wallet alert for one year
  back and 1 day intervals.
  """

  import Sanbase.Alert.OperationEvaluation

  alias Sanbase.Project
  alias Sanbase.Clickhouse.HistoricalBalance
  alias Sanbase.Alert.Trigger.EthWalletTriggerSettings

  require Logger

  @historical_days_from 365
  @historical_interval "1h"

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          balance: float(),
          triggered?: boolean()
        }

  def get_data(%{target: target, asset: %{slug: asset}}) do
    {from, to, interval} = get_timeseries_params()

    case addresses_from_target(target) do
      [] ->
        {:error, "No ethereum addresses provided or the target does not have ethereum addreses."}

      addresses ->
        result =
          addresses
          |> Enum.map(fn address ->
            {:ok, result} =
              HistoricalBalance.historical_balance(
                %{infrastructure: "ETH", slug: asset},
                address,
                from,
                to,
                interval
              )

            result
          end)
          |> Enum.zip()
          |> Stream.map(&Tuple.to_list/1)
          |> Enum.map(fn [%{datetime: dt} | _] = balances ->
            balance = Enum.map(balances, & &1.balance) |> Enum.sum()
            %{datetime: dt, balance: balance}
          end)

        {:ok, result}
    end
  end

  defp addresses_from_target(%{slug: slug}) when is_binary(slug) do
    {:ok, eth_addresses} =
      slug
      |> Project.by_slug()
      |> Project.eth_addresses()

    eth_addresses
  end

  defp addresses_from_target(%{eth_address: eth_address}) when is_binary(eth_address),
    do: eth_address |> List.wrap()

  defp get_timeseries_params() do
    now = Timex.now()
    from = Timex.shift(now, days: -@historical_days_from)

    {from, now, @historical_interval}
  end

  defimpl Sanbase.Alert.History, for: EthWalletTriggerSettings do
    alias Sanbase.Alert.Operation
    alias Sanbase.Alert.History.EthWalletTriggerHistory

    @spec historical_trigger_points(%EthWalletTriggerSettings{}, String.t()) ::
            {:ok, []}
            | {:ok, list(EthWalletTriggerHistory.historical_trigger_points_type())}
            | {:error, String.t()}
    def historical_trigger_points(
          %EthWalletTriggerSettings{target: %{slug: slug}} = settings,
          cooldown
        )
        when is_binary(slug) do
      do_historical_trigger_points(settings, cooldown)
    end

    def historical_trigger_points(
          %EthWalletTriggerSettings{target: %{eth_address: eth_address}} = settings,
          cooldown
        )
        when is_binary(eth_address) do
      do_historical_trigger_points(settings, cooldown)
    end

    def historical_trigger_points(%EthWalletTriggerSettings{}, _cooldown) do
      {:error, "The target can only be a single slug or a single ethereum address"}
    end

    defp do_historical_trigger_points(%EthWalletTriggerSettings{} = settings, cooldown) do
      case Operation.type(settings.operation) do
        :absolute ->
          evaluate(settings, cooldown)

        :percent ->
          {:error, "Historical trigger points for percent change are not implemented"}
      end
    end

    defp evaluate(settings, cooldown) do
      case EthWalletTriggerHistory.get_data(settings) do
        {:error, error} ->
          {:error, error}

        {:ok, []} ->
          {:ok, []}

        {:ok, data} ->
          mark_triggered(data, settings, cooldown)
      end
    end

    defp mark_triggered(data, settings, cooldown) do
      [%{balance: first_balance} | _] = data
      %{operation: operation} = settings

      cooldown_in_hours = Sanbase.DateTimeUtils.str_to_hours(cooldown)

      {acc, _, _} =
        data
        |> Enum.reduce({[], first_balance, 0}, fn
          %{balance: balance} = elem, {acc, previous_balance, 0} ->
            if operation_triggered?(balance - previous_balance, operation) do
              {
                [Map.put(elem, :triggered?, true) | acc],
                balance,
                cooldown_in_hours
              }
            else
              {
                [Map.put(elem, :triggered?, false) | acc],
                balance,
                0
              }
            end

          elem, {acc, _previous_balance, cooldown_left} ->
            {
              [Map.put(elem, :triggered?, false) | acc],
              elem.balance,
              cooldown_left - 1
            }
        end)

      result = acc |> Enum.reverse()
      {:ok, result}
    end
  end
end

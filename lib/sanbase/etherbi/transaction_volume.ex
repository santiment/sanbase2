defmodule Sanbase.Etherbi.TransactionVolume do
  @moduledoc ~S"""
    This module is a GenServer that periodically sends requests to etherbi API.
    Transaction volume is fetched and saved in a time series database for
    easier aggregation and querying.
  """

  @default_update_interval 1000 * 60 * 5

  use Sanbase.Etherbi.EtherbiGenServer

  require Logger

  alias Sanbase.Etherbi.Utils
  alias Sanbase.Etherbi.TransactionVolume.{Store, Fetcher}

  def work() do
    # Precalculate the number by which we have to divide, that is pow(10, decimal_places)
    token_decimals = Utils.build_token_decimals_map()
    tickers = Utils.get_tickers()

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      tickers,
      &fetch_and_store(&1, token_decimals),
      max_concurency: 1,
      timeout: 10 * 60_000
    )
    |> Stream.run()
  end

  def fetch_and_store(ticker, token_decimals) do
    with {:ok, transaction_volumes} <- Fetcher.transaction_volume(ticker) do
      convert_to_measurement(transaction_volumes, ticker, token_decimals)
      |> Store.import()
    else
      {:error, reason} ->
        Logger.warn("Could not fetch and store burn rate for #{ticker}: #{reason}")
    end
  end

  # Private functions

  # Better return no information than wrong information. If we have no data for the
  # number of decimal places `nil` is written instead and it gets filtered by the Store.import()
  defp convert_to_measurement(
         transaction_volumes,
         ticker,
         token_decimals
       ) do
    transaction_volumes
    |> Enum.map(fn {datetime, transaction_volume} ->
      %Sanbase.Influxdb.Measurement{
        timestamp: datetime |> DateTime.to_unix(:nanoseconds),
        fields: %{transaction_volume: transaction_volume / Map.get(token_decimals, ticker)},
        tags: [],
        name: ticker
      }
    end)
  end
end

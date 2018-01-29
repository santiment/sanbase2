defmodule Sanbase.Etherbi.TransactionVolume do
  @moduledoc ~S"""
    This module is a GenServer that periodically sends requests to etherbi API.
    Transaction volume is fetched and saved in a time series database for
    easier aggregation and querying.
  """

  @default_update_interval 1000 * 60 * 5

  use Sanbase.Etherbi.EtherbiGenServer

  import Ecto.Query

  require Logger

  alias Sanbase.Etherbi.TransactionVolume.Store
  alias Sanbase.Repo
  alias Sanbase.Model.Project

  def work() do
    # Precalculate the number by which we have to divide, that is pow(10, decimal_places)
    token_decimals = build_token_decimals_map()

    query = from(p in Project, where: not is_nil(p.ticker), select: p.ticker)
    tickers = Repo.all(query)

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      tickers,
      &fetch_and_store(&1, token_decimals),
      max_concurency: 1,
      timeout: 170_000
    )
    |> Stream.run()
  end

  def fetch_and_store(ticker, token_decimals) do
    with {:ok, transaction_volume} <- Sanbase.Etherbi.TransactionVolume.Fetcher.transaction_volume(ticker) do
      convert_to_measurement(transaction_volume, ticker, token_decimals)
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
      if decimal_places = Map.get(token_decimals, ticker) do
        %Sanbase.Influxdb.Measurement{
          timestamp: datetime |> DateTime.to_unix(:nanoseconds),
          fields: %{transaction_volume: transaction_volume / decimal_places},
          tags: [],
          name: ticker
        }
      else
        Logger.warn("Missing token decimals for #{ticker}")
        nil
      end
    end)
  end
end
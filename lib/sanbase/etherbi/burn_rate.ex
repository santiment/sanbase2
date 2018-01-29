defmodule Sanbase.Etherbi.BurnRate do
  @moduledoc ~S"""
    This module is a GenServer that periodically sends requests to etherbi API.
    Token burn rate is fetched and saved in a time series database for
    easier aggregation and querying.
  """

  @default_update_interval 1000 * 60 * 5

  use Sanbase.Etherbi.EtherbiFetcher

  import Ecto.Query

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Etherbi.BurnRate.{Store, Fetcher}
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
      timeout: 165_000
    )
    |> Stream.run()
  end

  def fetch_and_store(ticker, token_decimals) do
    with {:ok, burn_rates} <- Fetcher.burn_rate(ticker) do
      convert_to_measurement(burn_rates, ticker, token_decimals)
      |> Store.import()
    else
      {:error, reason} ->
        Logger.warn("Could not fetch and store out transactions for #{ticker}: #{reason}")
    end
  end

  # Private functions

  # Better return no information than wrong information. If we have no data for the
  # number of decimal places `nil` is written instead and it gets filtered by the Store.import()
  defp convert_to_measurement(
         burn_rates,
         ticker,
         token_decimals
       ) do
    burn_rates
    |> Enum.map(fn {datetime, burn_rate} ->
      if decimal_places = Map.get(token_decimals, ticker) do
        %Sanbase.Influxdb.Measurement{
          timestamp: datetime |> DateTime.to_unix(:nanoseconds),
          fields: %{burn_rate: burn_rate / decimal_places},
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
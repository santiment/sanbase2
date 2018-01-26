defmodule Sanbase.Etherbi.BurnRate do
  @moduledoc ~S"""
    This module is a GenServer that periodically sends requests to etherbi API.
    Token burn rate is fetched and saved in a time series database for
    easier aggregation and querying.
  """

  @default_update_interval 1000 * 60 * 5
  use Sanbase.Etherbi.EtherbiFetcher

  import Ecto.Query

  alias Sanbase.Etherbi.BurnRate.Store
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
      timeout: 165_000
    )
    |> Stream.run()
  end

  def fetch_and_store(ticker, token_decimals) do

  end

  # Private functions

  # Better return no information than wrong information. If we have no data for the
  # number of decimal places `nil` is written instead and it gets filtered by the Store.import()
  defp convert_to_measurement(
         transactions_data,
         transaction_type,
         token_decimals
       ) do
    transactions_data
    |> Enum.map(fn {datetime, volume, address, token} ->
      if decimal_places = Map.get(token_decimals, token) do
        %Sanbase.Influxdb.Measurement{
          timestamp: datetime |> DateTime.to_unix(:nanoseconds),
          fields: %{volume: volume / decimal_places},
          tags: [transaction_type: transaction_type, address: address],
          name: token
        }
      else
        Logger.warn("Missing token decimals for #{token}")
        nil
      end
    end)
  end
end
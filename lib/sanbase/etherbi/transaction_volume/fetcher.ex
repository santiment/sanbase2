defmodule Sanbase.Etherbi.TransactionVolume.Fetcher do
  require Logger

  alias Sanbase.Etherbi.Utils

  @etherbi_api Mockery.of("Sanbase.Etherbi.EtherbiApi")

  @doc ~S"""
    Uses the etherbi API to fetch the transaction volume for a given ticker.
    The `from-to` time period could no exceed 1 month by default.
  """
  @spec transaction_volume(binary()) :: {:ok, list()} | {:error, binary()}
  def transaction_volume(ticker) do
    case Utils.generate_from_to_interval_unix(
           ticker,
           db_last_datetime: &Sanbase.Etherbi.TransactionVolume.Store.last_datetime/1,
           etherbi_first_timestamp: &@etherbi_api.get_first_transaction_timestamp_ticker/1
         ) do
      {from_datetime, to_datetime} ->
        Logger.info("Getting transaction volume for #{ticker}")
        @etherbi_api.get_transaction_volume(ticker, from_datetime, to_datetime)

      _ ->
        {:ok, []}
    end
  end
end

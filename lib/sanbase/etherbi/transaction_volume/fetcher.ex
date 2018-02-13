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
    from_datetime = choose_starting_time(ticker)

    case Utils.generate_from_to_interval_unix(from_datetime) do
      {from, to} ->
        Logger.info("Getting transaction volume for #{ticker}")
        @etherbi_api.get_transaction_volume(ticker, from, to)

      _ ->
        {:ok, []}
    end
  end

  defp choose_starting_time(ticker) do
    {:ok, from_datetime} = Sanbase.Etherbi.TransactionVolume.Store.last_datetime(ticker)

    if from_datetime do
      from_datetime
    else
      {:ok, from_datetime} = @etherbi_api.get_first_transaction_timestamp_ticker(ticker)
      from_datetime
    end
  end
end

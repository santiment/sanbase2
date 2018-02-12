defmodule Sanbase.Etherbi.BurnRate.Fetcher do
  @etherbi_api Mockery.of("Sanbase.Etherbi.EtherbiApi")

  require Logger

  alias Sanbase.Etherbi.Utils

  @doc ~S"""
    Queries the etherbi rest api for the burn rate of a ticker in a given period.
    The `from-to` time period could no exceed 1 month by default.
  """
  @spec burn_rate(binary()) :: {:ok, list()} | {:error, binary()}
  def burn_rate(ticker) do
    from_datetime = choose_starting_time(ticker)

    case Utils.generate_from_to_interval_unix(from_datetime) do
      {from, to} ->
        Logger.info("Getting burn rate for #{ticker}")
        @etherbi_api.get_burn_rate(ticker, from, to)

      _ ->
        {:ok, []}
    end
  end

  defp choose_starting_time(ticker) do
    {:ok, from_datetime} = Sanbase.Etherbi.BurnRate.Store.last_datetime(ticker)

    if from_datetime do
      from_datetime
    else
      {:ok, from_datetime} = @etherbi_api.get_first_burn_rate_timestamp(ticker)
      from_datetime
    end
  end
end

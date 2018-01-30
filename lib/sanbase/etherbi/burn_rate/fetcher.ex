defmodule Sanbase.Etherbi.BurnRate.Fetcher do
  @etherbi_api Mockery.of("Sanbase.Etherbi.EtherbiApi")

  require Logger

  alias Sanbase.Etherbi.Utils

  def burn_rate(ticker) do
    case Utils.generate_from_to_interval_unix(
           ticker,
           db_last_datetime: &Sanbase.Etherbi.BurnRate.Store.last_datetime/1,
           etherbi_first_timestamp: &@etherbi_api.get_first_burn_rate_timestamp/1
         ) do
      {from_datetime, to_datetime} ->
        Logger.info("Getting burn rate for #{ticker}")
        @etherbi_api.get_burn_rate(ticker, from_datetime, to_datetime)

      _ ->
        {:ok, []}
    end
  end
end
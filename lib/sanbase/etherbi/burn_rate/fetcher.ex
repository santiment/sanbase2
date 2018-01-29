defmodule Sanbase.Etherbi.BurnRate.Fetcher do
  @etherbi_api Mockery.of("Sanbase.Etherbi.EtherbiApi")

  require Logger

  alias Sanbase.Etherbi.BurnRate.Store

  def burn_rate(ticker) do
    case generate_from_to_interval_unix(ticker) do
      {from_datetime, to_datetime} ->
        Logger.info("Getting burn rate for #{ticker}")
        @etherbi_api.get_burn_rate(ticker, from_datetime, to_datetime)

      _ ->
        {:ok, []}
    end
  end

  # Private functions

  # Get a tuple `{from, to}` to use in a query or `nil` if there is no info.
  # If there is no record in the DB for that address and Etherbi's
  # first transaction volume timestamp API returns no result then there are no transactions
  # In that case return `nil` and detect in the caller that no query should be made
  defp generate_from_to_interval_unix(ticker) do
    # Returns {:ok, nil} if there are no records for that measurement
    {:ok, from_datetime} =
      Store.last_datetime(ticker)

    from_datetime =
      if from_datetime do
        from_datetime
      else
        {:ok, from_datetime} = @etherbi_api.get_first_burn_rate_timestamp(ticker)
        from_datetime
      end

    if from_datetime do
      to_datetime = Sanbase.Etherbi.Utils.calculate_to_datetime(from_datetime, DateTime.utc_now())

      {from_datetime, to_datetime}
    else
      nil
    end
  end

end
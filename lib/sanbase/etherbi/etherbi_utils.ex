defmodule Sanbase.Etherbi.Utils do

  # Get a tuple `{from, to}` to use in a query or `nil` if there is no info.
  # If there is no record in the DB for that address and Etherbi's
  # first transaction timestamp API returns no result then there are no transactions
  # In that case return `nil` and detect in the caller that no query should be made
  def generate_from_to_interval_unix(ticker) do
    # Returns {:ok, nil} if there are no records for that measurement
    {:ok, from_datetime} =
      Store.last_datetime(ticker)

    from_datetime =
      if from_datetime do
        from_datetime
      else
        {:ok, from_datetime} = @etherbi_api.get_first_transaction_timestamp(address)
        from_datetime
      end

    if from_datetime do
      to_datetime = calculate_to_datetime(from_datetime, DateTime.utc_now())

      {from_datetime, to_datetime}
    else
      nil
    end
  end

  # If the difference between the datetimes is too large the query will be too big
  # Allow the max difference between the datetimes to be 1 month
  defp calculate_to_datetime(from_datetime, to_datetime) do
    if DateTime.diff(to_datetime, from_datetime, :seconds) > @seconds_in_month do
      Sanbase.DateTimeUtils.seconds_after(@seconds_in_month, from_datetime)
    else
      to_datetime
    end
  end
end
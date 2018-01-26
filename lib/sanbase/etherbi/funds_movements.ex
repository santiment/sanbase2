defmodule Sanbase.Etherbi.FundsMovement do
  @moduledoc ~S"""
    Module that exposes functions for tracking in and out transactions. The functions
    in this module expect an address as an argument and they find the optimal time period
    interval for the query.
  """

  require Sanbase.Utils.Config
  require Logger

  alias Sanbase.Utils.Config
  alias Sanbase.Etherbi.Store

  @etherbi_api Mockery.of("Sanbase.Etherbi.EtherbiApi")
  @seconds_in_month 60 * 60 * 24 * 30

  @doc ~S"""
    Fetches all in transactions for a single address via the Etherbi API.
    The Etherbi API allows querying for more than one address so it expects a list of addresses.
    The single address is transformed into list and is json encoded.

    Returns `{:ok, list()}` on succesful request, `{:error, reason}` otherwise
  """
  @spec transactions_in(binary()) :: {:ok, list()} | {:error, binary()}
  def transactions_in(address) do
    transactions(address, "in")
  end

  @doc ~S"""
    Fetches all out transactions for a single address via the Etherbi API.
    The Etherbi API allows querying for more than one address so it expects a list of addresses.
    The single address is transformed into list and is json encoded.

    Returns `{:ok, list()}` on succesful request, `{:error, reason}` otherwise
  """
  @spec transactions_out(binary()) :: {:ok, list()} | {:error, binary()}
  def transactions_out(address) do
    transactions(address, "out")
  end

  # Private functions

  defp transactions(address, transaction_type) do
    Logger.info("Getting #{transaction_type} transactions for #{address}")

    case generate_from_to_interval_unix(address, transaction_type) do
      {from_unix, to_unix} ->
        etherbi_url = @etherbi_api.etherbi_url()
        url = "#{etherbi_url}/transactions_#{transaction_type}"

        options = [
          recv_timeout: 120_000,
          params: %{
            from_timestamp: from_unix,
            to_timestamp: to_unix,
            wallets: Poison.encode!([address])
          }
        ]

        @etherbi_api.get_transactions(url, options)

      _ ->
        {:ok, []}
    end
  end

  # Get a tuple `{from_unix, to_unix}` to use in a query or `nil` if there is no info.
  # If there is no record in the DB for that address and Etherbi's
  # first transaction timestamp API returns no result then there are no transactions
  # In that case return `nil` and detect in the caller that no query should be made
  defp generate_from_to_interval_unix(address, transaction_type) do
    # Returns {:ok, nil} if there are no records for that measurement
    {:ok, from_datetime} =
      Store.last_datetime_with_tag(address, "transaction_type", transaction_type)

    from_datetime =
      if from_datetime do
        from_datetime
      else
        {:ok, from_datetime} = @etherbi_api.get_first_transaction_timestamp(address)
        from_datetime
      end

    if  from_datetime do
      to_datetime = calculate_to_datetime(from_datetime, DateTime.utc_now())

      from_unix = DateTime.to_unix(from_datetime, :seconds)
      to_unix = DateTime.to_unix(to_datetime, :seconds)

      {from_unix, to_unix}
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
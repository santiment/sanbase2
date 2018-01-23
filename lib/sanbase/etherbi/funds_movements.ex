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
  @etherbi_url Config.module_get(Sanbase.Etherbi, :url)
  @month_in_seconds 60 * 60 * 24 * 30

  @doc ~S"""
    Fetches all in transactions for a single address via the Etherbi API.
    The Etherbi API allows querying for more than one address so it expects a list of addresses.
    The single address is transformed into list and is json encoded.

    Returns `{:ok, list()}` on succesful request, `{:error, reason}` otherwise
  """
  @spec transactions_in(binary()) :: {:ok, list()} | {:error, binary()}
  def transactions_in(address) do
    Logger.info("Getting in transactions for #{address}")

    {from_unix, to_unix} = generate_from_to_interval_unix(address, "in")

    url = "#{@etherbi_url}/transactions_in"
    options = [
      recv_timeout: 120_000,
      params: %{
        from_timestamp: from_unix,
        to_timestamp: to_unix,
        wallets: Poison.encode!([address])
      }
    ]

    @etherbi_api.get_transactions(url, options)
  end

  @doc ~S"""
    Fetches all out transactions for a single address via the Etherbi API.
    The Etherbi API allows querying for more than one address so it expects a list of addresses.
    The single address is transformed into list and is json encoded.

    Returns `{:ok, list()}` on succesful request, `{:error, reason}` otherwise
  """
  @spec transactions_out(binary()) :: {:ok, list()} | {:error, binary()}
  def transactions_out(address) do
    Logger.info("Getting out transactions for #{address}")

    {from_unix, to_unix} = generate_from_to_interval_unix(address, "in")

    url = "#{@etherbi_url}/transactions_out"

    options = [
      recv_timeout: 120_000,
      params: %{
        from_timestamp: from_unix,
        to_timestamp: to_unix,
        wallets: Poison.encode!([address])
      }
    ]

    @etherbi_api.get_transactions(url, options)
  end

  # Private functions

  # Allow querying for max to one month
  defp generate_from_to_interval_unix(address, transaction_type) do
    # Returns {:ok, nil} if there are no records for that measurement
    {:ok, from_datetime} = Store.last_datetime_with_tag(address, "transaction_type", transaction_type)
    {:ok, from_datetime} = from_datetime || @etherbi_api.get_first_transaction_timestamp(address)

    to_datetime = get_to_datetime(from_datetime, DateTime.utc_now())

    from_unix = DateTime.to_unix(from_datetime, :seconds)
    to_unix = DateTime.to_unix(to_datetime, :seconds)

    {from_unix, to_unix}
  end

  # If the difference between the datetimes is too large the query will be too big
  # Allow the max difference between the datetimes to be 1 month
  defp get_to_datetime(from_datetime, to_datetime) do
    if DateTime.diff(to_datetime, from_datetime, :seconds) > @month_in_seconds do
      Sanbase.DateTimeUtils.days_after(30, from_datetime)
    else
      to_datetime
    end
  end
end

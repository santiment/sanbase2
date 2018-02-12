defmodule Sanbase.Etherbi.Transactions.Fetcher do
  @moduledoc ~S"""
    Module that exposes functions for tracking in and out transactions. The functions
    in this module expect an address as an argument and they find the optimal time period
    interval for the query.
  """

  require Logger

  alias Sanbase.Etherbi.Transactions.Store
  alias Sanbase.Etherbi.Utils

  @etherbi_api Mockery.of("Sanbase.Etherbi.EtherbiApi")

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
    from_datetime = choose_starting_time(address, transaction_type)

    case Utils.generate_from_to_interval_unix(from_datetime) do
      {from, to} ->
        Logger.info("Getting #{transaction_type} transactions for #{address}")
        @etherbi_api.get_transactions(address, from, to, transaction_type)

      _ ->
        {:ok, []}
    end
  end

  defp choose_starting_time(address, trx_type) do
    {:ok, from_datetime} = Store.last_address_datetime(address, trx_type)

    if from_datetime do
      from_datetime
    else
      {:ok, from_datetime} = @etherbi_api.get_first_transaction_timestamp_addr(address)
      from_datetime
    end
  end
end

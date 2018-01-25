defmodule Sanbase.Etherbi.EtherbiApi do
  @moduledoc ~S"""
    All communication with the Etherbi API are done via this module. It supports:
    1. Query for fetching the timestamp for a transaction that happened in our out of
    a given wallet
    2. Query for fetching all in transactions for a wallet and given time period
    3. Query for fetching all out transactions for a wallet and given time period
  """

  require Logger
  require Sanbase.Utils.Config

  alias Sanbase.Utils.Config

  @etherbi_url Config.module_get(Sanbase.Etherbi, :url)

  @doc ~S"""
    Issues a GET request to Etherbi REST transactions API to fetch all in or out
    transactions for addresses in a the given time period

    Returns `{:ok, list()}` if the request is successful, `{:error, reason}`
    otherwise.
  """
  @spec get_first_transaction_timestamp(binary()) :: {:ok, list()} | {:error, binary()}
  def get_first_transaction_timestamp(address) do
    Logger.info("Getting the first transaction timestamp for address #{address}")
    url = "#{@etherbi_url}/first_transaction_timestamp?address=#{address}"
    options = [recv_timeout: 45_000]

    case HTTPoison.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        convert_timestamp_response(body)

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warn("Timeout trying to fetch the first transaction timestamp for #{address}")
        {:ok, nil}

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error,
         "Error status #{status} fetching first transaction timestamp for #{address}: #{
           body
         }"}

      error ->
        {:error,
         "Error fetching first transaction timestamp data for address #{address}: #{
           inspect(error)
         }"}
    end
  end

  @doc ~S"""
    Issues a GET request to Etherbi REST first transaction timestamp API to get
    the timestamp of the first transaction made for the given address

    Returns `{:ok, list()}` if the request is successful, `{:error, reason}`
      otherwise.
  """
  @spec get_transactions(binary(), Keyword.t()) :: {:ok, list()} | {:error, binary()}
  def get_transactions(url, options) do
    case HTTPoison.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        convert_transactions_response(body)

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warn("Timeout trying to fetch transactions for #{extract_address(options)}")
        {:ok, []}

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching for #{extract_address(options)}: #{body}"}

      error ->
        {:error, "Error fetching transactions data for #{extract_address(options)}: #{inspect(error)}"}
    end
  end

  # Private functions

  defp extract_address(options) do
    options[:params][:wallets]
  end

  defp convert_timestamp_response("[]") do
    {:ok, nil}
  end

  # Body is a string in the format `"[timestamp]"`
  defp convert_timestamp_response(body) do
    with {:ok, decoded_body} <- Poison.decode(body) do
      result = decoded_body |> hd |> DateTime.from_unix!()
      {:ok, result}
    end
  end

  defp convert_transactions_response(body) do
    with {:ok, decoded_body} <- Poison.decode(body) do
      result =
        decoded_body
        |> Enum.map(fn [timestamp, volume, address, token] ->
          {DateTime.from_unix!(timestamp), volume, address, token}
        end)

      {:ok, result}
    end
  end
end
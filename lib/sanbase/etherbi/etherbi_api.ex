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

  @doc ~S"""
    Returns the etherbi url
  """
  @spec etherbi_url() :: binary()
  def etherbi_url() do
    Config.module_get(Sanbase.Etherbi, :url)
  end

  @doc ~S"""
    Issues a GET request to Etherbi REST transactions API to fetch all in or out
    transactions for addresses in a the given time period

    Returns `{:ok, list()}` if the request is successful, `{:error, reason}`
    otherwise.
  """
  @spec get_first_transaction_timestamp(binary()) :: {:ok, list()} | {:error, binary()}
  def get_first_transaction_timestamp(address) do
    url = "#{etherbi_url()}/first_transaction_timestamp"
    options = [recv_timeout: 45_000, params: %{address: address}]

    case HTTPoison.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        convert_timestamp_response(body)

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warn("Timeout trying to fetch the first transaction timestamp for #{address}")
        {:ok, nil}

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error,
         "Error status #{status} fetching first transaction timestamp for #{address}: #{body}"}

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
  @spec get_transactions(binary(), %DateTime{}, %DateTime{}, binary()) :: {:ok, list()} | {:error, binary()}
  def get_transactions(address, from, to, transaction_type) do
    transaction_type = transaction_type |> String.downcase()
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)
    url = "#{etherbi_url()}/transactions_#{transaction_type}"

    options = [
      recv_timeout: 120_000,
      params: %{
        from_timestamp: from_unix,
        to_timestamp: to_unix,
        wallets: Poison.encode!([address])
      }
    ]

    case HTTPoison.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        convert_transactions_response(body)

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warn("Timeout trying to fetch transactions for #{extract_address(options)}")
        {:ok, []}

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching for #{extract_address(options)}: #{body}"}

      error ->
        {:error,
         "Error fetching transactions data for #{extract_address(options)}: #{inspect(error)}"}
    end
  end

  @doc ~S"""
    Issues a GET request to Etherbi REST burn rate API to get
    the burn rate for a given ticker

    Returns `{:ok, list()}` if the request is successful, `{:error, reason}`
    otherwise.
  """
  @spec get_burn_rate(binary(), %DateTime{}, %DateTime{}) :: {:ok, list()} | {:error, binary()}
  def get_burn_rate(ticker, from, to) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)
    url = "#{etherbi_url()}/burn_rate"

    options = [
      recv_timeout: 45_000,
      params: %{ticker: ticker, from_timestamp: from_unix, to_timestamp: to_unix}
    ]

    case HTTPoison.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        convert_burn_rate_response(body)

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warn("Timeout trying to fetch burn rate for #{ticker}")
        {:ok, []}

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching burn rate for #{ticker}: #{body}"}

      error ->
        {:error, "Error fetching burn rate for #{ticker}: #{inspect(error)}"}
    end
  end

  # Private functions

  defp extract_address(options) do
    options[:params][:wallets]
  end

  # Body is a string in the format `"[timestamp]"`
  defp convert_timestamp_response("[]"), do: {:ok, nil}
  defp convert_timestamp_response(body) do
    with {:ok, decoded_body} <- Poison.decode(body) do
      result = decoded_body |> hd |> DateTime.from_unix!()
      {:ok, result}
    end
  end

  # Body is a string in the format `[[timestamp,volume,address,token], [timestamp,...]]
  defp convert_transactions_response("[]"), do: {:ok, nil}
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

  # Body is a string in the format `[[timestamp,volume], [timestamp, volume], ...]
  defp convert_burn_rate_response("[]"), do: {:ok, nil}
  defp convert_burn_rate_response(body) do
    with {:ok, decoded_body} <- Poison.decode(body) do
      result =
        decoded_body
        |> Enum.map(fn [timestamp, volume] ->
          {DateTime.from_unix!(timestamp), volume}
        end)

      {:ok, result}
    end
  end
end
defmodule Sanbase.Etherbi.EtherbiApi do
  @moduledoc ~S"""
    All communication with the Etherbi API are done via this module
  """

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
    url = "#{@etherbi_url}/first_transaction_timestamp"
    options = [
      recv_timeout: 15_000,
      params: %{ address: address }
    ]

    case HTTPoison.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        convert_timestamp_response(body)

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching data from url #{url}: #{body}"}

      error ->
        {:error, "Error fetching first transaction timestamp data: #{inspect(error)}"}
    end
  end

  @doc ~S"""
    Issues a GET request to Etherbi REST first transaction timestamp API to get
    the timestamp of the first transaction made for the given address

    Returns `{:ok, list()}` if the request is successful, `{:error, reason}`
      otherwise.
  """
  @spec get_transactions(binary(), Keyword.t) :: {:ok, list()} | {:error, binary()}
  def get_transactions(url, options) do
    case HTTPoison.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        convert_transactions_response(body)

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching data from url #{url}: #{body}"}

      error ->
        {:error, "Error fetching transactions data: #{inspect(error)}"}
    end
  end

  # Private functions

  defp convert_timestamp_response(body) do
    with {:ok, decoded_body} <- Poison.decode(body) do
      result = decoded_body |> String.to_integer() |> DateTime.from_unix!()
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

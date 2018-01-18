defmodule Sanbase.Etherbi.FundsMovement do
  require Sanbase.Utils.Config
  require Logger
  alias Sanbase.Utils.Config

  @etherbi_url Config.module_get(Sanbase.Etherbi, :url)
  @http_client Mockery.of("HTTPoison")

  def transactions_in(wallets, from, to) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    url = "#{@etherbi_url}/transactions_in"

    options = [
      recv_timeout: 45_000,
      params: [
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"wallets", Poison.encode!(wallets)}
      ]
    ]

    get(url, options)
  end

  def transactions_out(wallets, from, to) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    wallets = Poison.encode!(wallets)

    url = "#{@etherbi_url}/transactions_out"

    options = [
      recv_timeout: 45_000,
      params: [
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"wallets", Poison.encode!(wallets)}
      ]
    ]

    get(url, options)
  end

  defp get(url, options) do
    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, result} <- Poison.decode(body) do
          result =
            result
            |> Enum.map(fn [timestamp, volume, address, token] ->
              {DateTime.from_unix!(timestamp), volume, address, token}
            end)

          {:ok, result}
        end

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching data from url #{url}: #{body}"}

      error ->
        {:error, "Error fetching data: #{inspect(error)}"}
    end
  end
end
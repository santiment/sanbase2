defmodule Sanbase.Etherbi.Movement do
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  @etherbi_url Config.module_get(Sanbase.Etherbi, :url)
  @http_client Mockery.of("HTTPoison")

  def transactions_in(from, to, wallets) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    url = "#{@etherbi_url}/transactions_in?&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}&wallets=#{inspect(wallets)}"
    options = [recv_timeout: 15_000]
    get(url, options)
  end

  def transactions_out(from_datetime, to_datetime, wallets) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    url = "#{@etherbi_url}/transactions_in?&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}&wallets=#{inspect(wallets)}"
    options = [recv_timeout: 15_000]
    get(url, options)
  end

  defp get(url, options) do
    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)
        result =
          result
          |> Enum.map(fn [timestamp, volume, address, token] ->
            {DateTime.from_unix!(timestamp), Decimal.new(volume), address, token}
          end)

        {:ok, result}

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching data for ticker #{ticker}: #{body}"}

      error ->
        {:error, "Error fetching data for ticker #{ticker}: #{inspect(error)}"}
    end
  end
end
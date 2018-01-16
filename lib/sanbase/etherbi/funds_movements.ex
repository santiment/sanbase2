defmodule Sanbase.Etherbi.FundsMovement do
  require Sanbase.Utils.Config
  require Logger
  alias Sanbase.Utils.Config

  @etherbi_url Config.module_get(Sanbase.Etherbi, :url)
  @http_client Mockery.of("HTTPoison")

  def transactions_in(from, to, wallets) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    url =
      "#{@etherbi_url}/transactions_in?&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}&wallets=#{
        inspect(wallets)
      }"

    options = [recv_timeout: 15_000]
    get(url, options)
  end

  def transactions_out(from, to, wallets) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    wallets = Poison.encode!(wallets)

    url =
      "#{@etherbi_url}/transactions_in?from_timestamp=#{from_unix}&to_timestamp=#{to_unix}&wallets=#{
        inspect(wallets)
      }"

    Logger.info("#{inspect(url)}")
    options = [recv_timeout: 15_000]
    get(url, options)
  end

  defp get(_, _) do
    [
      {DateTime.from_unix!(1_514_765_134), 400_000_000_000_000_000_000,
       "0xfe9e8709d3215310075d67e3ed32a380ccf451c8", "SAN"},
      {DateTime.from_unix!(1_514_765_415), 400_000_000_000_000_000_000,
       "0xfe9e8709d3215310075d67e3ed32a380ccf451c8", "SAN"}
    ]
  end

  defp get(url, options) do
    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} = res ->
        IO.inspect(res)
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn [timestamp, volume, address, token] ->
            {DateTime.from_unix!(timestamp), volume, address, token}
          end)

        {:ok, result}

      {:error, %HTTPoison.Response{status_code: status, body: body}} = res ->
        IO.inspect(res)

        {:error, "Error status #{status} fetching data: #{body}"}

      error ->
        IO.inspect(error)
        {:error, "Error fetching data: #{inspect(error)}"}
    end
  end
end
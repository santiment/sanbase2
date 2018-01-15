defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  @http_client Mockery.of("HTTPoison")
  @recv_timeout 15_000
  @max_result_size 500

  def burn_rate(_root, %{ticker: ticker, from: from, to: to}, _resolution) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    etherbi_url = Config.get(:url)
    url = "#{etherbi_url}/burn_rate?ticker=#{ticker}&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}"

    options = [recv_timeout: @recv_timeout]
    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)
        result =
          result
          |> reduce_result_size(&average/1)
          |> Enum.map(fn [timestamp, br] ->
            %{datetime: DateTime.from_unix!(timestamp), burn_rate: Decimal.new(br)}
          end)

        {:ok, result}

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching burn rate for ticker #{ticker}: #{body}"}

      _ ->
        {:error, "Cannot fetch burn rate data for ticker #{ticker}"}
    end
  end

  def transaction_volume(_root, %{ticker: ticker, from: from, to: to}, _resolution) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    etherbi_url = Config.get(:url)
    url = "#{etherbi_url}/transaction_volume?ticker=#{ticker}&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}"

    options = [recv_timeout: @recv_timeout]
    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> reduce_result_size(&Enum.sum/1)
          |> Enum.map(fn [timestamp, trx_volume] ->
            %{datetime: DateTime.from_unix!(timestamp), transaction_volume: Decimal.new(trx_volume)}
          end)

        {:ok, result}

      {:error, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching transaction volume for ticker #{ticker}: #{body}"}

      _ ->
        {:error, "Cannot fetch burn transaction volume for ticker #{ticker}"}
    end
  end

  defp reduce_result_size(list, _) when length(list) < 2 * @max_result_size, do: list

  defp reduce_result_size(list, reduce_function) do
    chunk_size = trunc(length(list) / @max_result_size)

    list
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(fn chunk ->
      [
        min_timestamp(chunk),
        reduced_value(chunk, reduce_function)
      ]
    end)
  end

  defp min_timestamp(chunk) do
    chunk
    |> Enum.map(&hd/1)
    |> Enum.min
  end

  defp reduced_value(chunk, reduce_function) do
    chunk
    |> Enum.map(&tl/1)
    |> Enum.map(&hd/1)
    |> reduce_function.()
  end

  defp average(list) do
    Enum.sum(list) / length(list)
  end
end

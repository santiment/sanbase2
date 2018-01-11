defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  use Tesla

  import Sanbase.Utils, only: [parse_config_value: 1]

  plug(Tesla.Middleware.BaseUrl, get_config(:url))
  plug(Tesla.Middleware.Logger)

  def burn_rate(_root, %{ticker: ticker, from: from, to: to}, _resolution) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    case get("/burn_rate?ticker=#{ticker}&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}") do
      %Tesla.Env{status: 200, body: body} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn [timestamp, br] ->
            %{datetime: DateTime.from_unix!(timestamp), burn_rate: Decimal.new(br)}
          end)

        {:ok, result}

      %Tesla.Env{status: status, body: body} ->
        {:error, "Error status #{status} fetching burn rate for ticker #{ticker}: #{body}"}

      _ ->
        {:error, "Cannot fetch burn rate data for ticker #{ticker}"}
    end
  end

  def transaction_volume(_root, %{ticker: ticker, from: from, to: to}, _resolution) do
    from_unix = DateTime.to_unix(from, :seconds)
    to_unix = DateTime.to_unix(to, :seconds)

    case get("/transaction_volume?ticker=#{ticker}&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}") do
      %Tesla.Env{status: 200, body: body} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn [timestamp, trx_volume] ->
            %{datetime: DateTime.from_unix!(timestamp), transaction_volume: Decimal.new(trx_volume)}
          end)

        {:ok, result}

      %Tesla.Env{status: status, body: body} ->
        {:error, "Error status #{status} fetching transaction volume for ticker #{ticker}: #{body}"}

      _ ->
        {:error, "Cannot fetch burn transaction volume for ticker #{ticker}"}
    end
  end

  defp get_config(key) do
    Application.fetch_env!(:sanbase, __MODULE__)
    |> Keyword.get(key)
    |> parse_config_value()
  end
end
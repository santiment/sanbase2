defmodule Sanbase.WalletHunters.RelayerApi do
  @relayer_url "http://san-rewards-relay.default.svc.cluster.local/"
  @opts [recv_timeout: 20000]

  # Only for testing
  def generate_request do
    Path.join(@relayer_url, "/test/generate_request")
    |> HTTPoison.get([], @opts)
    |> handle_response()
  end

  def relay(request, signature) do
    data = Map.merge(request, %{signature: signature}) |> Jason.encode!()

    Path.join(@relayer_url, "/relay")
    |> HTTPoison.post(data, [], @opts)
    |> handle_response()
  end

  def transaction(transaction_id) do
    Path.join(@relayer_url, "/transaction/#{transaction_id}")
    |> HTTPoison.get([], @opts)
    |> handle_response()
  end

  defp handle_response(response) do
    response
    |> case do
      {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
        {:ok, Jason.decode!(body)}

      response ->
        {:error, response}
    end
  end
end

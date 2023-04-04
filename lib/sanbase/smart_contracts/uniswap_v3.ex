defmodule Sanbase.SmartContracts.UniswapV3 do
  @uniswap_v3_pool "0x345bec0d86f156294e6602516284c19bd449be1e"

  @query """
  query($pool: String!) {
    positions(first: 999, where: {pool: $pool}) {
      owner
      depositedToken0
      depositedToken1
    }
  }
  """

  def get_deposited_san_tokens() do
    get_uniswap_v3_nfts()
    |> case do
      {:ok, %{"positions" => positions}} ->
        Enum.reduce(positions, %{}, fn p, acc ->
          Map.update(
            acc,
            p["owner"],
            Sanbase.Math.to_float(p["depositedToken0"]),
            &(&1 + Sanbase.Math.to_float(p["depositedToken0"]))
          )
        end)

      _ ->
        %{}
    end
  end

  def get_deposited_san_tokens(address) do
    get_deposited_san_tokens()
    |> Map.get(address, 0)
  end

  def get_uniswap_v3_nfts() do
    url = "https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3"
    variables = %{"pool" => @uniswap_v3_pool}
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(%{"query" => @query, "variables" => variables})

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, decoded_response} = Jason.decode(response_body)
        {:ok, Map.get(decoded_response, "data", %{})}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end

defmodule Sanbase.SmartContracts.UniswapV3 do
  @san_contract "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
  @weth_contract "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
  @uniswap_v3_pool "0x345bec0d86f156294e6602516284c19bd449be1e"

  @query """
  query($pool: String!) {
    positions(where: {pool: $pool}) {
      owner
      depositedToken0
      depositedToken1
    }
  }
  """

  def get_deposited_san_tokens(address) do
    get_uniswap_v3_nfts(address)
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

  def get_uniswap_v3_nfts(owner) do
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

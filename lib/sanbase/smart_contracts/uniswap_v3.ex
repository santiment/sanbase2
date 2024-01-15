defmodule Sanbase.SmartContracts.UniswapV3 do
  @uniswap_v3_san_weth_pool "0x345bec0d86f156294e6602516284c19bd449be1e"

  @query """
  query($pool: String!, $first: Int!, $skip: Int!) {
    positions(first: $first, skip: $skip, where: {pool: $pool}) {
      owner
      depositedToken0
      depositedToken1
    }
  }
  """

  def get_all_deposited_san_tokens() do
    get_uniswap_v3_nfts(%{first: 100, skip: 0})
  end

  defp get_uniswap_v3_nfts(%{first: first, skip: skip}, acc \\ []) do
    case fetch(%{pool: @uniswap_v3_san_weth_pool, first: first, skip: skip}) do
      {:ok, %{"positions" => []}} ->
        acc

      {:ok, %{"positions" => positions}} ->
        get_uniswap_v3_nfts(%{first: first, skip: skip + first}, acc ++ positions)

      _ ->
        []
    end
  end

  def get_deposited_san_tokens(address) do
    address = String.downcase(address)
    positions = get_all_deposited_san_tokens()

    positions_map =
      Enum.reduce(positions, %{}, fn p, acc ->
        token0 = Sanbase.Math.to_float(p["depositedToken0"])

        Map.update(
          acc,
          p["owner"],
          token0,
          &(&1 + token0)
        )
      end)

    positions_map |> Map.get(address, 0)
  end

  def fetch(variables) do
    url = "https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3"
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

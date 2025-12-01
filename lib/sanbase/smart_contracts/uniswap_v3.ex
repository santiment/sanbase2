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

  def fetch(variables) do
    # Url for the Uniswap V3 subgraph changed to the gateway.thegraph.com and needs an API key
    # https://thegraph.com/studio/apikeys/ - create an API key for the subgraph
    # Free plan has 100K requests per month
    thegraph_api_key = System.get_env("THEGRAPH_API_KEY")

    url =
      "https://gateway.thegraph.com/api/#{thegraph_api_key}/subgraphs/id/5zvR82QoaXYFyDEKLZ9t6v9adgnptxYpKpSbxtgVENFV"

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

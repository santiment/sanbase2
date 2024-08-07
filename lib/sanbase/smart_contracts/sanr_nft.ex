defmodule Sanbase.SmartContracts.SanrNFT do
  @doc ~s"""
  Get all the owners of NFTs obtained by spending SanR reward points
  Returns a map where the address is the key, and a map with token_id is the value
  """
  def get_all_nft_owners() do
    req = Req.new(base_url: "https://zksync-mainnet.g.alchemy.com")

    params = [
      {"contractAddress", "0x0476448242d4eca3FfB0DB57116E47177340e0d3"},
      {"withTokenBalances", "true"}
    ]

    {:ok, nft_metadata} = get_all_nft_expiration_dates()

    result =
      Req.get(req, url: "/nft/v3/#{alchemy_api_key()}/getOwnersForContract", params: params)

    case result do
      {:ok, %{status: 200, body: body}} ->
        %{"owners" => owners, "pageKey" => nil} = body

        # In case the address holds multiple NFTs, the one with the latest `end_date` is
        # returned.
        map =
          Map.new(owners, fn
            %{
              "ownerAddress" => address,
              "tokenBalances" => token_balances
            } ->
              token_id = extract_latest_token_id(token_balances, nft_metadata)
              address = Sanbase.BlockchainAddress.to_internal_format(address)
              {address, %{token_id: token_id}}

            _ ->
              {nil, nil}
          end)

        {:ok, map}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Get all the issued NFTs' start date and end dates.
  Returns a map where the token id is the key and the value is a map with start_date and end_date.
  End date is 12 months after start date. Holding this NFT grants you Sanbae PRO subscription
  until its end date.
  """
  def get_all_nft_expiration_dates() do
    req =
      Req.new(
        base_url:
          "https://sanrnew-api.production.internal.santiment.net/api/v1/SanbaseSubscriptionNFTCollection/all"
      )

    result = Req.get(req, [])

    case result do
      {:ok, %{status: 200, body: body}} ->
        map =
          Map.new(body, fn m ->
            {m["id"],
             %{
               start_date: Sanbase.DateTimeUtils.from_iso8601!(m["subscription_start_date"]),
               end_date: Sanbase.DateTimeUtils.from_iso8601!(m["subscription_end_date"])
             }}
          end)

        {:ok, map}

      {:error, error} ->
        {:error, error}
    end
  end

  def extract_latest_token_id(token_balances, nft_metadata) do
    token_balances
    |> Enum.filter(fn %{"balance" => balance} -> balance == "1" end)
    |> Enum.map(fn map -> Map.update!(map, "tokenId", &String.to_integer/1) end)
    |> Enum.max_by(fn %{"tokenId" => token_id} -> nft_metadata[token_id].end_date end, DateTime)
    |> Map.get("tokenId")
  end

  defp alchemy_api_key() do
    Sanbase.Utils.Config.module_get(__MODULE__, :alchemy_api_key)
  end
end

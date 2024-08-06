defmodule Sanbase.SmartContracts.SanbaseNFTInterface do
  alias Sanbase.Accounts.User

  def nft_subscriptions(%User{} = user) do
    user = Sanbase.Repo.preload(user, :eth_accounts)

    nft_data =
      user.eth_accounts
      |> Enum.map(fn ea ->
        address = String.downcase(ea.address)
        data = Sanbase.SmartContracts.SanbaseNFT.nft_subscriptions_data(address)

        %{
          address: address,
          token_ids: data.valid,
          non_valid_token_ids: data.non_valid
        }
      end)

    %{
      nft_data: nft_data,
      has_valid_nft: has_valid_nft?(nft_data),
      has_non_valid_nft: has_non_valid_nft?(nft_data),
      nft_count: nft_count(nft_data),
      non_valid_nft_count: non_valid_nft_count(nft_data)
    }
  end

  def nft_subscriptions(user_id) when is_integer(user_id) do
    User.by_id(user_id)
    |> case do
      {:ok, user} ->
        nft_subscriptions(user)

      {:error, _} ->
        %{
          nft_data: %{},
          has_valid_nft: false,
          nft_count: 0,
          non_valid_nft_count: 0,
          has_non_valid_nft: false
        }
    end
  end

  defp has_valid_nft?(data) do
    data
    |> Enum.filter(fn %{token_ids: token_ids} -> length(token_ids) > 0 end)
    |> Enum.any?()
  end

  defp has_non_valid_nft?(data) do
    data
    |> Enum.filter(fn %{non_valid_token_ids: token_ids} -> length(token_ids) > 0 end)
    |> Enum.any?()
  end

  defp nft_count(data) do
    data
    |> Enum.reduce(0, fn %{token_ids: token_ids}, acc -> acc + length(token_ids) end)
  end

  defp non_valid_nft_count(data) do
    data
    |> Enum.reduce(0, fn %{non_valid_token_ids: non_valid_token_ids}, acc ->
      acc + length(non_valid_token_ids)
    end)
  end
end

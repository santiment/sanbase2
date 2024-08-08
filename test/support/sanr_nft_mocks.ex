defmodule Sanbase.SanrNFTMocks do
  def get_owners_for_contract_mock(address) do
    {:ok,
     %Req.Response{
       status: 200,
       headers: %{},
       body: %{
         "owners" => [
           %{
             "ownerAddress" => address,
             "tokenBalances" => [
               %{"balance" => "1", "tokenId" => "1"},
               %{"balance" => "1", "tokenId" => "2"}
             ]
           }
         ],
         "pageKey" => nil
       },
       trailers: %{},
       private: %{}
     }}
  end

  def sanr_nft_collections_mock(start_date, end_date) do
    {:ok,
     %Req.Response{
       status: 200,
       headers: %{},
       body: [
         %{
           "id" => 1,
           "sanr_points_amount" => 10000,
           "subscription_end_date" => end_date,
           "subscription_start_date" => start_date
         },

         # This one is expired. Added here so we can test what happens when
         # one address holds multiple NFTs
         %{
           "id" => 2,
           "sanr_points_amount" => 10000,
           "subscription_end_date" => ~U[2024-05-05 00:00:00Z],
           "subscription_start_date" => ~U[2023-05-05 00:00:00Z]
         }
       ],
       trailers: %{},
       private: %{}
     }}
  end
end

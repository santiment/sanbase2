defmodule Sanbase.ExternalServices.Etherscan.FetchTransactions do
  use SanbaseWeb.ConnCase

  import Mockery

  alias Sanbase.ExternalServices.Etherscan.{Worker, Store}
  alias Sanbase.ExternalServices.Etherscan.Requests.{Tx, InternalTx}
  alias Sanbase.Model.{Project, ProjectEthAddress}
  alias Sanbase.Repo

  setup do
    Store.create_db()

    ticker = "SAN"
    address = "0x123245678910"
    cmc_id = "santiment"

    p =
      %Project{}
      |> Project.changeset(%{
        name: "Santiment",
        ticker: ticker,
        token_decimals: 18,
        coinmarketcap_id: cmc_id
      })
      |> Repo.insert!()

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{project_id: p.id, address: address})
    |> Repo.insert!()

    [
      ticker: ticker,
      address: address,
      cmc_id: cmc_id
    ]
  end

  test "fetch internal transactions", context do
    mock(
      Sanbase.ExternalServices.Etherscan.Requests.Tx,
      :get,
      {:ok,
       [
         %Tx{
           blockNumber: "4470352",
           from: "0x123245678910",
           isError: "0",
           timeStamp: 1_509_541_164,
           to: "0xd1ea8853619aaad66f3f6c14ca22430ce6954476",
           txreceipt_status: "1",
           value: "0"
         },
         %Tx{
           blockNumber: "4463670",
           from: "0x123245678910",
           isError: "0",
           timeStamp: 1_509_448_322,
           to: "0xd1ea8853619aaad66f3f6c14ca22430ce6954476",
           txreceipt_status: "1",
           value: "1000000000000000000"
         },
         %Tx{
           blockNumber: "4463588",
           from: "0x8e473843fd546bf203f8b96cce310bb8740a4cec",
           isError: "0",
           timeStamp: 1_509_447_419,
           to: "0x123245678910",
           txreceipt_status: "1",
           value: "680000000000000000"
         }
       ]}
    )

    mock(
      Sanbase.ExternalServices.Etherscan.Requests.InternalTx,
      :get,
      {:ok,
       [
         %InternalTx{
           blockNumber: "4557084",
           errCode: "",
           from: "0x123245678910",
           isError: "0",
           timeStamp: 1_510_746_716,
           to: "0x949342479c00fccd65fee93a6b5a4fbd9b4abcea",
           value: "4000000000000000000000"
         },
         %InternalTx{
           blockNumber: "4379313",
           errCode: "",
           from: "0x7da82c7ab4771ff031b66538d2fb9b0b047f6cf9",
           isError: "0",
           timeStamp: 1_508_276_361,
           to: "0x123245678910",
           value: "3000000000000000000000"
         },
         %Sanbase.ExternalServices.Etherscan.Requests.InternalTx{
           blockNumber: "4173006",
           errCode: "",
           from: "0x7da82c7ab4771ff031b66538d2fb9b0b047f6cf9",
           isError: "0",
           timeStamp: 1_503_053_188,
           to: "0x123245678910",
           value: "10000000000000000000000"
         }
       ]}
    )

    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        __client__: nil,
        __module__: Sanbase.ExternalServices.Etherscan.Requests,
        body: %{
          "message" => "OK",
          "result" => "198474700000000000000000",
          "status" => "1"
        },
        headers: %{
          "access-control-allow-headers" => "Content-Type",
          "access-control-allow-methods" => "GET, POST, OPTIONS",
          "access-control-allow-origin" => "*",
          "cache-control" => "private",
          "content-length" => "65",
          "content-type" => "application/json; charset=utf-8",
          "date" => "Wed, 14 Feb 2018 14:28:40 GMT",
          "server" => "Microsoft-IIS/10.0",
          "x-frame-options" => "SAMEORIGIN"
        },
        method: :get,
        opts: [],
        query: [
          module: "account",
          action: "balance",
          address: "0x123245678910",
          tag: "latest",
          apikey: nil
        ],
        status: 200,
        url: "https://api.etherscan.io/api/"
      }
    end)

    endblock = 999_999_999

    Worker.fetch_and_store(
      %{address: context.address, coinmarketcap_id: context.cmc_id},
      endblock
    )

    assert {:ok, 113_000.68} =
             Store.trx_sum_in_interval(
               context.cmc_id,
               DateTime.from_unix!(0),
               DateTime.utc_now(),
               "in"
             )

    assert {:ok, 24001} =
             Store.trx_sum_in_interval(
               context.cmc_id,
               DateTime.from_unix!(0),
               DateTime.utc_now(),
               "out"
             )
  end
end

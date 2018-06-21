defmodule Sanbase.ExternalServices.Etherscan.FetchTransactions do
  use SanbaseWeb.ConnCase, async: false

  import Mockery

  alias Sanbase.ExternalServices.Etherscan.{Worker, Store}
  alias Sanbase.ExternalServices.Etherscan.Requests.{Tx, InternalTx}
  alias Sanbase.Model.{Project, ProjectEthAddress}
  alias Sanbase.Repo

  setup do
    ticker = "SAN"
    address = "0x123245678910"
    cmc_id = "santiment"

    Store.create_db()
    Store.drop_measurement(ticker)

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

  test "fetch transactions", context do
    mock(
      Sanbase.ExternalServices.Etherscan.Requests.Tx,
      :get,
      {:ok,
       [
         %Tx{
           hash: "0x123456788c",
           blockNumber: "4470352",
           from: "0x123245678910",
           isError: "0",
           timeStamp: 1_509_541_164,
           to: "0xd1ea8853619aaad66f3f6c14ca22430ce6954476",
           txreceipt_status: "1",
           value: 10 |> ether_to_wei_str()
         },
         %Tx{
           hash: "0x123456788b",
           blockNumber: "4463670",
           from: "0x123245678910",
           isError: "0",
           timeStamp: 1_509_448_322,
           to: "0xd1ea8853619aaad66f3f6c14ca22430ce6954476",
           txreceipt_status: "1",
           value: 10 |> ether_to_wei_str()
         },
         %Tx{
           hash: "0x123456788a",
           blockNumber: "4463588",
           from: "0x8e473843fd546bf203f8b96cce310bb8740a4cec",
           isError: "0",
           timeStamp: 1_509_447_419,
           to: "0x123245678910",
           txreceipt_status: "1",
           value: 500 |> ether_to_wei_str()
         }
       ]}
    )

    mock(
      Sanbase.ExternalServices.Etherscan.Requests.InternalTx,
      :get,
      {:ok,
       [
         %InternalTx{
           hash: "0x123456789c",
           blockNumber: "4557084",
           errCode: "",
           from: "0x123245678910",
           isError: "0",
           timeStamp: 1_510_746_716,
           to: "0x949342479c00fccd65fee93a6b5a4fbd9b4abcea",
           value: 50 |> ether_to_wei_str()
         },
         %InternalTx{
           hash: "0x123456789a",
           blockNumber: "4379313",
           errCode: "",
           from: "0x7da82c7ab4771ff031b66538d2fb9b0b047f6cf9",
           isError: "0",
           timeStamp: 1_508_276_361,
           to: "0x123245678910",
           value: 1000 |> ether_to_wei_str()
         },
         %Sanbase.ExternalServices.Etherscan.Requests.InternalTx{
           hash: "0x123456789b",
           blockNumber: "4173006",
           errCode: "",
           from: "0x7da82c7ab4771ff031b66538d2fb9b0b047f6cf9",
           isError: "0",
           timeStamp: 1_503_053_188,
           to: "0x123245678910",
           value: 200 |> ether_to_wei_str()
         }
       ]}
    )

    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        __client__: nil,
        __module__: Sanbase.ExternalServices.Etherscan.Requests,
        body: %{
          "message" => "OK",
          "result" => 11111 |> ether_to_wei_str(),
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
      %{address: context.address, ticker: context.ticker},
      endblock
    )

    assert {:ok, 1700} =
             Store.trx_sum_in_interval(
               context.ticker,
               DateTime.from_unix!(0),
               DateTime.utc_now(),
               "in"
             )

    assert {:ok, 70} =
             Store.trx_sum_in_interval(
               context.ticker,
               DateTime.from_unix!(0),
               DateTime.utc_now(),
               "out"
             )
  end

  # Helper functions
  def ether_to_wei_str(num) when is_number(num) do
    # Do not use scientifix notation, otherwise to_string fails
    (num * :math.pow(10, 18))
    |> Kernel.trunc()
    |> Integer.to_string()
  end
end

defmodule Sanbase.ExternalServices.Etherscan.Requests do

  #require Logger
  use Tesla


  alias Sanbase.ExternalServices.Etherscan.RateLimiter
  alias Sanbase.ExternalServices.Etherscan.Requests

  plug RateLimiter.Tesla
  plug Tesla.Middleware.BaseUrl, "https://api.etherscan.io/api"
  plug Tesla.Middleware.Compression

  plug Tesla.Middleware.Query, [
    apikey: Keyword.get(config(), :apikey)
  ]
  plug Tesla.Middleware.Logger

  defmodule Balance do
    defstruct [:status, :message, :result]

    defp get_query(address) do
      [
        module: "account",
        action: "balance",
        address: address,
        tag: "latest",
      ]
    end

    def get(address) do
      Requests.get("/", query: get_query(address))
      |> case do
           %{status: 200, body: body} -> Poison.decode!(body, as: %Balance{})
         end
    end
  end

  defmodule InternalTx do
    defstruct [:blockNumber,
               :timeStamp,
               :hash,
	       :from,
              :to,
              :value,
              :contractAddress,
              :input,
              :type,
              :gas,
              :gasUsed,
              :traceId,
              :isError,
              :errCode
             ]
    
    defp get_query(address) do
      [
       module: "account",
       action: "txlistinternal",
       address: address,
       startblock: 0,
       endblock: 99999999,
       sort: "asc",
      ]
    end

    def get(address) do
      Requests.get("/", query: get_query(address))
      |> case do
          %{status: 200, body: body} -> 
              response = Poison.decode!(body, as: %{result: [%InternalTx{}]})
              response.result
        end
    end
  end

  defmodule Tx do
    defstruct [:blockNumber,
              :timeStamp,
              :hash,
              :nonce,
              :blockHash,
              :transactionIndex,
              :from,
              :to,
              :value,
              :gas,
              :gasPrice,
              :isError,
              :txreceipt_status,
              :input,
              :contractAddress,
              :cumulativeGasUsed,
              :gasUsed,
              :confirmations
             ]

    defp get_query(address, startblock, endblock) do
      [
       module: "account",
       action: "txlist",
       address: address,
       startblock: startblock,
       endblock: endblock,
       sort: "desc"
      ]
    end

    def get(address, startblock, endblock) do
      Requests.get("/", query: get_query(address, startblock, endblock))
      |> case do
          %{status: 200, body: body} ->
            parse_tx_json(body)
        end
    end

    defp parse_tx_json(body) do
      response = Poison.decode!(body, as: %{"result" => [%Tx{}]})
      response["result"]
      |> Enum.map( fn(tx)->
       {ts, ""} = Integer.parse(tx.timeStamp)
       %{tx | timeStamp: ts}
      end)
    end


    def get_last_outgoing_transaction(address, startblock, endblock) do
      normalized_address = String.downcase(address)
      get(address, startblock, endblock)
      |> Enum.find(fn(tx)->
       String.downcase(tx.from) == normalized_address
      end)
    end
  end

  def get_latest_block_number do
    get("/",
      query: [
       module: "proxy",
       action: "eth_BlockNumber"
      ])
    |> case do
        %{status: 200, body: body} -> parse_latest_block_number(body)
       end
  end

  def parse_latest_block_number(body) do
    result = Poison.decode!(body)
    {res, ""} = result["result"]
    |> String.slice(2..-1)
    |> Integer.parse(16)
    res
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end
end

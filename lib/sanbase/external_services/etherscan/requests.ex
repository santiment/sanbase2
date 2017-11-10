defmodule Sanbase.ExternalServices.Etherscan.Requests do

  use Tesla

  require Logger

  alias Sanbase.ExternalServices.Etherscan.RateLimiter
  alias Sanbase.ExternalServices.Etherscan.Requests
  
  @average_block_time_s 10 #Actually it is close to 15, but we get a safety net this way
  @default_timespan_s 7*24*60*60 # 1 week

  plug RateLimiter.Tesla
  plug Tesla.Middleware.BaseUrl, "https://api.etherscan.io/api"
  plug Tesla.Middleware.Compression
  #plug Tesla.Middleware.DebugLogger
  plug Tesla.Middleware.Opts, [
    method: :get,
    url: "/"
  ]

  plug Tesla.Middleware.Query, [
    apikey: "myapikey" #TODO
  ]
  

  defmodule Balance do
    defstruct [:status, :message, :result]
    
    defp get_query(address) do
      [
	method: :get,
	query: [
	  module: "account",
	  action: "balance",
	  address: address,
	  tag: "latest",
	]
      ]
    end

    def get(address) do
      address
      |> get_query()
      |> Requests.request()
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
	query: [
	  module: "account",
	  action: "txlistinternal",
	  address: address,
	  startblock: 0,
	  endblock: 99999999,
	  sort: "asc",
	]
      ]
    end

    def get(address) do
      address
      |> get_query()
      |> Requests.request()
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
	query: [
	  module: "account",
	  action: "txlist",
	  address: address,
	  startblock: startblock,
	  endblock: endblock,
	  sort: "desc"
	]
      ]
    end

    def get(address, startblock, endblock) do
      get_query(address, startblock, endblock)
      |> Requests.request()
      |> case do
	   %{status: 200, body: body} ->
	     parse_tx_json(body)
	 end
    end

    defp parse_tx_json(body) do
      response = Poison.decode!(body, as: %{"result" => [%Tx{}]})
      response["result"]
      |> Enum.map( fn(tx)->
	Logger.info("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
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
    Requests.request([
      query: [
	module: "proxy",
	action: "eth_BlockNumber"
      ]
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

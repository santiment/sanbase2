defmodule Sanbase.ExternalServices.Etherscan.InternalTxTest do
  use SanbaseWeb.ConnCase, async: false

  test "internal tx get and parse" do
    Tesla.Mock.mock(fn %{
                         method: :get,
                         url: "https://graphs2.coinmarketcap.com/currencies/santiment/"
                       } ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "btc_graph_data.json"))}
    end)
  end
end

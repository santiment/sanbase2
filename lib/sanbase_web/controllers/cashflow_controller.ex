defmodule SanbaseWeb.CashflowController do
  use SanbaseWeb, :controller
  alias Sanbase.Cashflow

  require IEx

  def index(conn, _params) do
    data = Cashflow.get_project_data

    data = Enum.group_by(data,
      fn(el) ->
        %{project: el.project, coinmarketcap: el.coinmarketcap}
      end,
      fn(el) ->
        el.wallet_data
      end)

    data = Enum.map(data,
      fn({k, v}) ->
        market_cap_usd = if (k.coinmarketcap !== nil), do: k.coinmarketcap.market_cap_usd, else: nil
        wallet_data = Enum.filter(v, fn(x) -> x !== nil end)
        wallet_data = Enum.map(wallet_data, fn(el) -> %{address: el.address, balance: el.balance, last_outgoing: el.last_outgoing, tx_out: el.tx_out} end)
        balance = Enum.reduce(wallet_data, 0, fn(x, acc) -> x.balance + acc end)
        %{
          name: k.project.name,
          ticker: k.project.ticker,
          logo_url: k.project.logo_url,
          market_cap_usd: market_cap_usd,
          balance: balance,
          wallets: wallet_data
        }
      end)

    # TODO: fetch eth_price
    eth_price = 3.14

    data = %{eth_price: eth_price, projects: data}

    # IEx.pry

    render conn, "index.json", project_data: data
  end
end

defmodule SanbaseWeb.CashflowView do
  use SanbaseWeb, :view

  def render("index.json", %{eth_price: eth_price, projects: projects}) do

    projects = projects
    |> Enum.group_by(&Map.take(&1, [:project, :coinmarketcap]), &(&1.wallet_data))
    |> Enum.map(&construct_project_data(&1))

    %{eth_price: eth_price, projects: projects}

    # %{
    #   eth_price: 123.456,
    #   projects:
    #   [
    #     %{
    #       name: "project1",
    #       ticker: "P1",
    #       logo_url: "aragon.png",
    #       market_cap_usd: 333.555,
    #       balance: 432.55,
    #       wallets:
    #       [
    #         %{
    #           address: "p1_address1",
    #           balance: 4324.22,
    #           last_outgoing: "2015-01-23 23:50:07",
    #           tx_out: 32.44
    #         },
    #         %{
    #           address: "p1_address2",
    #           balance: 44.33,
    #           last_outgoing: "2016-01-23 23:50:07",
    #           tx_out: 542.44
    #         }
    #       ]
    #     }
    #   ]
    # }
  end

  defp construct_project_data({%{project: project, coinmarketcap: coinmarketcap}, wallets}) do
    market_cap_usd = if (coinmarketcap !== nil), do: coinmarketcap.market_cap_usd, else: nil

    wallets = construct_wallet_data(wallets)

    balance = Enum.reduce(wallets, 0, fn(x, acc) -> x.balance + acc end)

    %{
      name: project.name,
      ticker: project.ticker,
      logo_url: project.logo_url,
      market_cap_usd: market_cap_usd,
      balance: balance,
      wallets: wallets
    }
  end

  defp construct_wallet_data(wallets) do
    wallets
    |> Enum.filter(&(&1 !== nil))
    |> Enum.map(&Map.take(&1, [:address, :balance, :last_outgoing, :tx_out]))
  end

end

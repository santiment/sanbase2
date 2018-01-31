defmodule SanbaseWeb.CashflowView do
  use SanbaseWeb, :view

  alias Decimal, as: D

  def render("index.json", %{eth_price: eth_price, projects: projects}) do
    projects =
      projects
      |> Enum.group_by(&Map.take(&1, [:project, :coinmarketcap]), & &1.wallet_data)
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
    market_cap_usd = if coinmarketcap !== nil, do: coinmarketcap.market_cap_usd, else: nil

    wallets = construct_wallet_data(wallets)

    balance = Enum.reduce(wallets, D.new(0), fn x, acc -> D.add(x.balance, acc) end) |> D.round(2)

    %{
      id: project.id,
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
    |> Enum.map(&format_wallet/1)
  end

  defp format_wallet(wallet) do
    wallet
    |> Map.update(:balance, D.new(0), &round_decimal/1)
    |> Map.update(:tx_out, D.new(0), &round_decimal/1)
    |> Map.take([:address, :balance, :last_outgoing, :tx_out])
  end

  defp round_decimal(nil) do
    nil
  end

  defp round_decimal(num) do
    D.round(num, 2)
  end
end

defmodule SanbaseWeb.CashflowView do
  use SanbaseWeb, :view

  def render("index.json", %{project_data: project_data}) do

    project_data

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
end

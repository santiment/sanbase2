defmodule SanbaseWeb.ProjectsView do
  use SanbaseWeb, :view

  def render("index.json", %{projects: projects}) do
    projects
    |> Enum.filter(& &1.latest_coinmarketcap_data)
    |> Enum.map(fn project ->
      %{
        name: project.name,
        coinmarketcap_id: project.coinmarketcap_id,
        ticker: project.ticker,
        website_link: project.website_link,
        price_usd: project.latest_coinmarketcap_data.price_usd,
        market_cap_usd: project.latest_coinmarketcap_data.market_cap_usd
      }
    end)
  end
end

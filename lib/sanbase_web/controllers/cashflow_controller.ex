defmodule SanbaseWeb.CashflowController do
  use SanbaseWeb, :controller

  alias Sanbase.Cashflow
  alias Sanbase.ExternalServices.Coinbase

  def index(conn, _params) do
    project_data = Cashflow.get_project_data

    eth_price = Coinbase.get_eth_price

    render conn, "index.json", eth_price: eth_price, projects: project_data
  end
end

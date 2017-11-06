defmodule Sanbase.Notifications.CheckPricesTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Notifications.CheckPrices
  alias Sanbase.Model.Project
  alias Sanbase.Prices.{Store, Point}
  alias Sanbase.Repo

  test "running the checks when there are no projects" do
    CheckPrices.exec
  end

  test "running the checks for a project without prices" do
    Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    CheckPrices.exec
  end

  test "running the checks for a project with some prices" do
    Store.drop_pair("SAN_USD")
    Store.import_price_points([
      %Point{datetime: seconds_ago(5), price: 1, volume: 1, marketcap: 1},
      %Point{datetime: seconds_ago(4), price: 2, volume: 1, marketcap: 1},
      %Point{datetime: seconds_ago(3), price: 3, volume: 1, marketcap: 1},
      %Point{datetime: seconds_ago(2), price: 4, volume: 1, marketcap: 1},
    ],
    "SAN_USD")
    Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    CheckPrices.exec
  end

  defp seconds_ago(seconds) do
    DateTime.utc_now()
    |> DateTime.to_unix()
    |> Kernel.-(seconds)
    |> DateTime.from_unix!
  end
end

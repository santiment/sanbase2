defmodule Sanbase.Notifications.CheckPricesTest do
  use Sanbase.DataCase, async: false
  use Mockery

  alias Sanbase.Notifications.{CheckPrices, Notification}
  alias Sanbase.Model.Project
  alias Sanbase.Prices.{Store, Measurement}
  alias Sanbase.Repo

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  test "running the checks when there are no projects" do
    assert CheckPrices.exec == []
  end

  test "running the checks for a project without prices" do
    Store.drop_pair("SAN_USD")
    Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    assert CheckPrices.exec == []
  end

  test "running the checks for a project with some prices" do
    Store.drop_pair("SAN_USD")
    Store.import([
      %Measurement{timestamp: seconds_ago(5) |> DateTime.to_unix(:nanoseconds), fields: %{price: 1.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Measurement{timestamp: seconds_ago(4) |> DateTime.to_unix(:nanoseconds), fields: %{price: 2.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Measurement{timestamp: seconds_ago(3) |> DateTime.to_unix(:nanoseconds), fields: %{price: 3.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Measurement{timestamp: seconds_ago(2) |> DateTime.to_unix(:nanoseconds), fields: %{price: 4.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
    ])
    project = Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    mock Tesla, [post: 3], %{status: 200}

    [%Notification{project_id: project_id}] = CheckPrices.exec

    assert project_id == project.id
    assert_called Tesla, post: 3
  end
end

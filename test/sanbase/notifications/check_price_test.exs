defmodule Sanbase.Notifications.CheckPricesTest do
  use Sanbase.DataCase, async: false
  use Mockery

  alias Sanbase.Notifications.{CheckPrices, Notification}
  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Repo

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  setup do
    Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Store.execute()
  end

  test "running the checks for a project without prices" do
    Store.drop_measurement("SAN_USD")

    project =
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    assert CheckPrices.exec(project, "usd") == false
  end

  test "running the checks for a project with some prices" do
    Store.drop_measurement("SAN_USD")

    Store.import([
      %Measurement{
        timestamp: seconds_ago(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 1.0, volume: 1, marketcap: 1.0},
        name: "SAN_USD"
      },
      %Measurement{
        timestamp: seconds_ago(4) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 2.0, volume: 1, marketcap: 1.0},
        name: "SAN_USD"
      },
      %Measurement{
        timestamp: seconds_ago(3) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 3.0, volume: 1, marketcap: 1.0},
        name: "SAN_USD"
      },
      %Measurement{
        timestamp: seconds_ago(2) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 4.0, volume: 1, marketcap: 1.0},
        name: "SAN_USD"
      }
    ])

    project =
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    mock(Tesla, [post: 3], %{status: 200})

    %Notification{project_id: project_id} = CheckPrices.exec(project, "usd")

    assert project_id == project.id
    assert_called(Tesla, post: 3)
  end
end

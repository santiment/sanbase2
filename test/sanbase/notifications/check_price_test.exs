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
    Store.create_db()
  end

  test "running the checks for a project without prices" do
    slug = "santiment"
    ticker = "SAN"
    ticker_cmc_id = ticker <> "_" <> slug
    Store.drop_measurement(ticker_cmc_id)

    project =
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    assert CheckPrices.exec(project, "USD") == false
  end

  test "running the checks for a project with some prices" do
    slug = "santiment"
    ticker = "SAN"
    ticker_cmc_id = ticker <> "_" <> slug
    Store.drop_measurement(ticker_cmc_id)

    project =
      %Project{}
      |> Project.changeset(%{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})
      |> Repo.insert!()

    Store.import([
      %Measurement{
        timestamp: seconds_ago(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{price_usd: 1.0, volume_usd: 1, marketcap_usd: 1.0},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: seconds_ago(4) |> DateTime.to_unix(:nanoseconds),
        fields: %{price_usd: 2.0, volume_usd: 1, marketcap_usd: 1.0},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: seconds_ago(3) |> DateTime.to_unix(:nanoseconds),
        fields: %{price_usd: 3.0, volume_usd: 1, marketcap_usd: 1.0},
        name: ticker_cmc_id
      },
      %Measurement{
        timestamp: seconds_ago(2) |> DateTime.to_unix(:nanoseconds),
        fields: %{price_usd: 4.0, volume_usd: 1, marketcap_usd: 1.0},
        name: ticker_cmc_id
      }
    ])

    mock(Tesla, [post: 3], %{status: 200})

    %Notification{project_id: project_id} = CheckPrices.exec(project, "USD")

    assert project_id == project.id
    assert_called(Tesla, post: 3)
  end
end

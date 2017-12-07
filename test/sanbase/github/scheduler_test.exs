defmodule Sanbase.Github.SchedulerTest do
  use Sanbase.DataCase, async: false
  use Mockery

  alias Sanbase.Github.Scheduler
  alias Sanbase.Model.Project
  alias Sanbase.Prices
  alias Sanbase.Github
  alias Sanbase.Repo

  setup do
    Application.fetch_env!(:sanbase, Sanbase.Github.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Github.Store.execute()

    Application.fetch_env!(:sanbase, Sanbase.ExternalServices.Coinmarketcap)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Prices.Store.execute()
  end

  test "nothing is scheduled if there are no projects with github links" do
    Prices.Store.drop_pair("SAN_USD")
    Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    mock SanbaseWorkers.ImportGithubActivity, [perform_async: 1], :ok

    Scheduler.schedule_scrape()

    refute_called SanbaseWorkers.ImportGithubActivity, perform_async: 1
  end

  test "scheduling projects with some pricing data but no activity" do
    Github.Store.drop_ticker("SAN")

    Prices.Store.drop_pair("SAN_USD")
    Prices.Store.import([
      %Prices.Measurement{timestamp: days_ago(5) |> DateTime.to_unix(:nanoseconds), fields: %{price: 1.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Prices.Measurement{timestamp: days_ago(4) |> DateTime.to_unix(:nanoseconds), fields: %{price: 2.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Prices.Measurement{timestamp: days_ago(3) |> DateTime.to_unix(:nanoseconds), fields: %{price: 3.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Prices.Measurement{timestamp: days_ago(2) |> DateTime.to_unix(:nanoseconds), fields: %{price: 4.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
    ])
    Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment", github_link: "https://github.com/santiment"})

    mock SanbaseWorkers.ImportGithubActivity, [perform_async: 1], :ok

    Scheduler.schedule_scrape()

    assert_called SanbaseWorkers.ImportGithubActivity, :perform_async, [_], 120 # 5 days, 24 hours each
  end

  test "scheduling projects with some pricing data and some activity" do
    Prices.Store.drop_pair("SAN_USD")
    Prices.Store.import([
      %Prices.Measurement{timestamp: days_ago(5) |> DateTime.to_unix(:nanoseconds), fields: %{price: 1.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Prices.Measurement{timestamp: days_ago(4) |> DateTime.to_unix(:nanoseconds), fields: %{price: 2.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Prices.Measurement{timestamp: days_ago(3) |> DateTime.to_unix(:nanoseconds), fields: %{price: 3.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
      %Prices.Measurement{timestamp: days_ago(2) |> DateTime.to_unix(:nanoseconds), fields: %{price: 4.0, volume: 1, marketcap: 1.0}, name: "SAN_USD"},
    ])

    Github.Store.drop_ticker("SAN")
    Github.Store.import([
      %Github.Measurement{timestamp: days_ago(5) |> DateTime.to_unix(:nanoseconds), fields: %{activity: 1}, name: "SAN"},
      %Github.Measurement{timestamp: days_ago(4) |> DateTime.to_unix(:nanoseconds), fields: %{activity: 2}, name: "SAN"},
      %Github.Measurement{timestamp: days_ago(3) |> DateTime.to_unix(:nanoseconds), fields: %{activity: 1}, name: "SAN"},
    ])

    Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment", github_link: "https://github.com/santiment"})

    mock SanbaseWorkers.ImportGithubActivity, [perform_async: 1], :ok

    Scheduler.schedule_scrape()

    assert_called SanbaseWorkers.ImportGithubActivity, :perform_async, [_], 72 # 3 days, 24 hours each
  end

  defp days_ago(days) do
    Timex.today()
    |> Timex.shift(days: -days)
    |> Timex.end_of_day()
    |> Timex.to_datetime()
  end
end

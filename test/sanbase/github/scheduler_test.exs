defmodule Sanbase.Github.SchedulerTest do
  use Sanbase.DataCase, async: false
  use Mockery

  alias Sanbase.Github.Scheduler
  alias Sanbase.Model.Project
  alias Sanbase.Prices
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Github
  alias Sanbase.Repo

  setup do
    Application.fetch_env!(:sanbase, Sanbase.Github.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Github.Store.execute()

    Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Prices.Store.execute()
  end

  test "nothing is scheduled if there are no projects with github links" do
    Prices.Store.drop_measurement("SAN_santiment")
    Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    mock(SanbaseWorkers.ImportGithubActivity, [perform_async: 1], :ok)

    Scheduler.schedule_scrape()

    refute_called(SanbaseWorkers.ImportGithubActivity, perform_async: 1)
  end

  test "scheduling projects with some pricing data but no activity" do
    measurement_name = "SAN_santiment"
    Github.Store.drop_measurement("SAN")

    Prices.Store.drop_measurement(measurement_name)

    Prices.Store.import([
      %Measurement{
        timestamp: days_ago_start_of_day(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 1.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(4) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 2.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(3) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 3.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(2) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 4.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      }
    ])

    Repo.insert!(%Project{
      name: "Santiment",
      ticker: "SAN",
      coinmarketcap_id: "santiment",
      github_link: "https://github.com/santiment"
    })

    mock(SanbaseWorkers.ImportGithubActivity, [perform_async: 1], :ok)

    Scheduler.schedule_scrape()

    # 5 days, 24 hours each
    assert_called(SanbaseWorkers.ImportGithubActivity, :perform_async, [_], 120)
  end

  test "scheduling projects with some pricing data and some activity" do
    measurement_name = "SAN_santiment"
    Prices.Store.drop_measurement("SAN_santiment")

    Prices.Store.import([
      %Measurement{
        timestamp: days_ago_start_of_day(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 1.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(4) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 2.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(3) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 3.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(2) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 4.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      }
    ])

    Github.Store.drop_measurement("SAN")

    Github.Store.import([
      %Measurement{
        timestamp: days_ago_start_of_day(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 1},
        name: "SAN"
      },
      %Measurement{
        timestamp: days_ago_start_of_day(4) |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 2},
        name: "SAN"
      },
      %Measurement{
        timestamp: days_ago_start_of_day(3) |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 1},
        name: "SAN"
      }
    ])

    Repo.insert!(%Project{
      name: "Santiment",
      ticker: "SAN",
      coinmarketcap_id: "santiment",
      github_link: "https://github.com/santiment"
    })

    mock(SanbaseWorkers.ImportGithubActivity, [perform_async: 1], :ok)

    Scheduler.schedule_scrape()

    # 3 days, 24 hours each
    assert_called(SanbaseWorkers.ImportGithubActivity, :perform_async, [_], 72)
  end

  test "scheduling projects which has processed archives" do
    measurement_name = "SAN_santiment"
    Prices.Store.drop_measurement("measurement_name")

    Prices.Store.import([
      %Measurement{
        timestamp: days_ago_start_of_day(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 1.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(4) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 2.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(3) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 3.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      },
      %Measurement{
        timestamp: days_ago_start_of_day(2) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 4.0, volume: 1, marketcap: 1.0},
        name: measurement_name
      }
    ])

    measurement_name2 = "OMG_omisego"
    Prices.Store.drop_measurement(measurement_name2)

    Prices.Store.import([
      %Measurement{
        timestamp: days_ago_start_of_day(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 1.0, volume: 1, marketcap: 1.0},
        name: measurement_name2
      }
    ])

    Github.Store.drop_measurement("SAN")

    san_project =
      Repo.insert!(%Project{
        name: "Santiment",
        ticker: "SAN",
        coinmarketcap_id: "santiment",
        github_link: "https://github.com/santiment"
      })

    omg_project =
      Repo.insert!(%Project{
        name: "OmiseGo",
        ticker: "OMG",
        coinmarketcap_id: "omisego",
        github_link: "https://github.com/omisego"
      })

    mock(SanbaseWorkers.ImportGithubActivity, [perform_async: 1], :ok)

    mark_as_processed_interval(san_project.id, days_ago_start_of_day(5), days_ago_start_of_day(1))
    mark_as_processed_interval(omg_project.id, days_ago_start_of_day(5), days_ago_start_of_day(2))

    Scheduler.schedule_scrape()

    # 2 days
    assert_called(SanbaseWorkers.ImportGithubActivity, :perform_async, [_], 48)
  end

  defp mark_as_processed_interval(project_id, from_datetime, to_datetime) do
    case DateTime.compare(from_datetime, to_datetime) do
      :lt ->
        archive_name = Scheduler.archive_name_for(from_datetime)
        Github.ProcessedGithubArchive.mark_as_processed(project_id, archive_name)

        next_datetime =
          from_datetime
          |> Timex.shift(hours: 1)

        mark_as_processed_interval(project_id, next_datetime, to_datetime)

      _ ->
        :ok
    end
  end

  defp days_ago_start_of_day(days) do
    Timex.today()
    |> Timex.shift(days: -days)
    |> Timex.end_of_day()
    |> Timex.to_datetime()
  end
end

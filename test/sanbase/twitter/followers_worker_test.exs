defmodule Sanbase.Twitter.FollowersWorkerTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [generate_dates_inclusive: 2, date_to_datetime: 1]

  alias Sanbase.Twitter.MetricAdapter, as: TwitterFollowers

  setup do
    Sanbase.InMemoryKafka.Producer.clear_state()

    projects = Enum.map(1..5, fn _ -> insert(:random_erc20_project) end)

    [projects: projects]
  end

  test "schedule twitter followers migration work", context do
    %{projects: projects} = context

    from = ~D[2021-01-01]
    to = ~D[2021-01-10]

    data = data(from, to)

    Sanbase.Mock.prepare_mock2(&TwitterFollowers.available_slugs/0, {:ok, projects})
    |> Sanbase.Mock.prepare_mock2(&TwitterFollowers.first_datetime/2, {:ok, from})
    |> Sanbase.Mock.prepare_mock2(&TwitterFollowers.last_datetime_computed_at/2, {:ok, to})
    |> Sanbase.Mock.prepare_mock2(&TwitterFollowers.timeseries_data/6, data)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Twitter.FollowersScheduler.add_jobs()
      Sanbase.Twitter.FollowersScheduler.resume()

      # Assert that all the jobs are enqueued
      for slug <- Enum.map(projects, & &1.slug) do
        assert_enqueued(
          worker: Sanbase.Twitter.FollowersWorker,
          args: %{
            slug: slug,
            from: from,
            to: to
          }
        )
      end

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 5, failure: 0} =
               Oban.drain_queue(queue: Sanbase.Twitter.FollowersWorker.queue())

      # Try to run the same jobs again
      Sanbase.Twitter.FollowersScheduler.add_jobs()

      # Assert that the jobs are not enqueued the secont time around
      for slug <- Enum.map(projects, & &1.slug) do
        refute_enqueued(
          worker: Sanbase.Twitter.FollowersWorker,
          args: %{
            slug: slug,
            from: from,
            to: to
          }
        )
      end

      slugs_freq =
        Sanbase.Twitter.FollowersScheduler.get_recorded_slugs()
        |> Enum.frequencies()

      # Make sure no jobs were runned more than once
      assert Enum.all?(slugs_freq, fn {_k, v} -> v == 1 end)

      state = Sanbase.InMemoryKafka.Producer.get_state()
      twitter_followers_topic = state["twitter_followers"]

      # 5 slugs with 10 records each
      assert length(twitter_followers_topic) == 50

      {:ok, data_points} = data

      assert Enum.uniq(twitter_followers_topic) ==
               data_points
               |> Enum.map(&Sanbase.Twitter.TimeseriesPoint.new/1)
               |> Enum.map(&Sanbase.Twitter.TimeseriesPoint.json_kv_tuple/1)
    end)
  end

  # Private Functions

  defp data(from, to) do
    timeseries_pairs =
      generate_dates_inclusive(from, to)
      |> Enum.map(fn date ->
        %{
          datetime: date_to_datetime(date),
          value: :rand.uniform(10_000)
        }
      end)

    {:ok, timeseries_pairs}
  end
end

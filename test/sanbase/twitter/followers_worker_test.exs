defmodule Sanbase.Twitter.FollowersWorkerTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [generate_dates_inclusive: 2, date_to_datetime: 1]

  alias Sanbase.Twitter
  alias Sanbase.Model.Project

  setup do
    Sanbase.InMemoryKafka.Producer.clear_state()

    slugs = Enum.map(1..5, fn _ -> insert(:random_erc20_project) end) |> Enum.map(& &1.slug)

    [slugs: slugs]
  end

  test "schedule twitter followers migration work", context do
    %{slugs: slugs} = context

    now = Timex.now()
    from = Timex.shift(now, days: -9)

    data = data(DateTime.to_date(from), DateTime.to_date(now))

    Sanbase.Mock.prepare_mock2(&Twitter.MetricAdapter.available_slugs/0, {:ok, slugs})
    |> Sanbase.Mock.prepare_mock2(&Twitter.MetricAdapter.first_datetime/2, {:ok, from})
    |> Sanbase.Mock.prepare_mock2(&Twitter.MetricAdapter.timeseries_data/6, {:ok, data})
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Twitter.FollowersScheduler.add_jobs()
      Sanbase.Twitter.FollowersScheduler.resume()

      # Assert that all the jobs are enqueued
      for slug <- slugs do
        assert_enqueued(
          worker: Sanbase.Twitter.FollowersWorker,
          args: %{
            slug: slug,
            from: from
          }
        )
      end

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 5, failure: 0} =
               Oban.drain_queue(Sanbase.Twitter.FollowersScheduler.conf_name(),
                 queue: Sanbase.Twitter.FollowersWorker.queue()
               )

      # Try to run the same jobs again
      Sanbase.Twitter.FollowersScheduler.add_jobs()

      # Assert that the jobs are not enqueued the second time around
      for slug <- slugs do
        refute_enqueued(
          worker: Sanbase.Twitter.FollowersWorker,
          args: %{
            slug: slug,
            from: from
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

      assert Enum.sort(twitter_followers_topic) ==
               transform_to_export_data(slugs, data) |> Enum.sort()
    end)
  end

  # Private Functions

  defp data(from, to) do
    generate_dates_inclusive(from, to)
    |> Enum.map(fn date ->
      %{
        datetime: date_to_datetime(date),
        value: :rand.uniform(10_000)
      }
    end)
  end

  defp transform_to_export_data(slugs, data) do
    slugs
    |> Enum.flat_map(&transform_to_export_data_for_slug(&1, data))
  end

  defp transform_to_export_data_for_slug(slug, data) do
    {:ok, twitter_handle} = Project.by_slug(slug) |> Project.twitter_handle()

    data
    |> Enum.map(&Map.put(&1, :twitter_handle, twitter_handle))
    |> Stream.map(&Sanbase.Twitter.TimeseriesPoint.new/1)
    |> Enum.map(&Sanbase.Twitter.TimeseriesPoint.json_kv_tuple/1)
  end
end

defmodule Sanbase.Twitter.FollowersWorkerTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.DateTimeUtils, only: [generate_dates_inclusive: 2, date_to_datetime: 1]
  import Sanbase.Factory

  alias Sanbase.InMemoryKafka.Producer
  alias Sanbase.Project
  alias Sanbase.Twitter
  alias Sanbase.Twitter.FollowersScheduler
  alias Sanbase.Twitter.FollowersWorker
  alias Sanbase.Twitter.TimeseriesPoint

  setup do
    Producer.clear_state()

    slugs = 1..5 |> Enum.map(fn _ -> insert(:random_erc20_project) end) |> Enum.map(& &1.slug)

    [slugs: slugs]
  end

  test "schedule twitter followers migration work", context do
    %{slugs: slugs} = context

    now = DateTime.utc_now()
    from = Timex.shift(now, days: -9)

    data = data(DateTime.to_date(from), DateTime.to_date(now))

    (&Twitter.MetricAdapter.available_slugs/0)
    |> Sanbase.Mock.prepare_mock2({:ok, slugs})
    |> Sanbase.Mock.prepare_mock2(&Twitter.MetricAdapter.first_datetime/2, {:ok, from})
    |> Sanbase.Mock.prepare_mock2(&Twitter.MetricAdapter.timeseries_data/6, {:ok, data})
    |> Sanbase.Mock.run_with_mocks(fn ->
      FollowersScheduler.add_jobs()
      FollowersScheduler.resume()

      # Assert that all the jobs are enqueued
      for slug <- slugs do
        assert_enqueued(
          worker: FollowersWorker,
          args: %{
            slug: slug,
            from: from
          }
        )
      end

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 5, failure: 0} =
               Oban.drain_queue(FollowersScheduler.conf_name(),
                 queue: FollowersWorker.queue()
               )

      # Try to run the same jobs again
      FollowersScheduler.add_jobs()

      # Assert that the jobs are not enqueued the second time around
      for slug <- slugs do
        refute_enqueued(
          worker: FollowersWorker,
          args: %{
            slug: slug,
            from: from
          }
        )
      end

      slugs_freq = Enum.frequencies(FollowersScheduler.get_recorded_slugs())

      # Make sure no jobs were runned more than once
      assert Enum.all?(slugs_freq, fn {_k, v} -> v == 1 end)

      state = Producer.get_state()
      twitter_followers_topic = state["twitter_followers"]

      # 5 slugs with 10 records each
      assert length(twitter_followers_topic) == 50

      assert Enum.sort(twitter_followers_topic) ==
               slugs |> transform_to_export_data(data) |> Enum.sort()
    end)
  end

  # Private Functions

  defp data(from, to) do
    from
    |> generate_dates_inclusive(to)
    |> Enum.map(fn date ->
      %{
        datetime: date_to_datetime(date),
        value: :rand.uniform(10_000)
      }
    end)
  end

  defp transform_to_export_data(slugs, data) do
    Enum.flat_map(slugs, &transform_to_export_data_for_slug(&1, data))
  end

  defp transform_to_export_data_for_slug(slug, data) do
    {:ok, twitter_handle} = slug |> Project.by_slug() |> Project.twitter_handle()

    data
    |> Enum.map(&Map.put(&1, :twitter_handle, twitter_handle))
    |> Stream.map(&TimeseriesPoint.new/1)
    |> Enum.map(&TimeseriesPoint.json_kv_tuple/1)
  end
end

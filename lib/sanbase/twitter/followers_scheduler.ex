defmodule Sanbase.Twitter.FollowersScheduler do
  use GenServer

  alias Sanbase.Twitter
  alias Sanbase.Twitter.FollowersWorker

  require Logger
  require Sanbase.Utils.Config, as: Config

  @oban_queue :twitter_followers_migration_queue

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def resume(), do: Oban.resume_queue(queue: @oban_queue)
  def pause(), do: Oban.pause_queue(queue: @oban_queue)

  def init(_opts) do
    # In order to be able to stop the historical scraper via env variables
    # the queue is defined as paused and should be resumed from code.
    if enabled?() do
      Logger.info(
        "[Twitter Followers Migration] Start exporting twitter followers timeseries data."
      )

      resume()
    end

    {:ok, %{}}
  end

  def enabled?(), do: Config.get(:enabled?) |> String.to_existing_atom()

  def add_jobs() do
    {:ok, slugs} = Twitter.MetricAdapter.available_slugs()

    (slugs -- get_recorded_slugs())
    |> Enum.map(&create_oban_job(&1))
    |> Oban.insert_all()
  end

  def get_recorded_slugs() do
    query = """
    SELECT args->>'slug' FROM oban_jobs
    """

    {:ok, %{rows: recorded_slugs}} = Ecto.Adapters.SQL.query(Sanbase.Repo, query)

    recorded_slugs
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  def create_oban_job(slug) do
    {:ok, first_datetime} =
      Twitter.MetricAdapter.first_datetime("twitter_followers", %{slug: slug})

    {:ok, last_datetime} =
      Twitter.MetricAdapter.last_datetime_computed_at("twitter_followers", %{slug: slug})

    FollowersWorker.new(%{slug: slug, from: first_datetime, to: last_datetime})
  end
end

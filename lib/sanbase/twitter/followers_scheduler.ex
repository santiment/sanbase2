defmodule Sanbase.Twitter.FollowersScheduler do
  @moduledoc false
  use GenServer

  alias Sanbase.Twitter
  alias Sanbase.Twitter.FollowersWorker

  require Logger
  require Sanbase.Utils.Config, as: Config

  @oban_conf_name :oban_scrapers
  @oban_queue :twitter_followers_migration_queue

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def conf_name, do: @oban_conf_name
  def resume, do: Oban.resume_queue(@oban_conf_name, queue: @oban_queue)
  def pause, do: Oban.pause_queue(@oban_conf_name, queue: @oban_queue)

  def init(_opts) do
    # In order to be able to stop the historical scraper via env variables
    # the queue is defined as paused and should be resumed from code.
    if enabled?() do
      Logger.info("[Twitter Followers Migration] Start exporting twitter followers timeseries data.")

      resume()
    end

    {:ok, %{}}
  end

  def enabled?, do: __MODULE__ |> Config.module_get(:enabled?) |> String.to_existing_atom()

  def add_jobs do
    {:ok, slugs} = Twitter.MetricAdapter.available_slugs()

    slugs_left = slugs -- get_recorded_slugs()
    data = Enum.map(slugs_left, &create_oban_job(&1))

    Oban.insert_all(@oban_conf_name, data)
  end

  def get_recorded_slugs do
    query = """
    SELECT DISTINCT args->>'slug' FROM oban_jobs
    WHERE queue = 'twitter_followers_migration_queue'
    """

    {:ok, %{rows: recorded_slugs}} = Ecto.Adapters.SQL.query(Sanbase.Repo, query)

    recorded_slugs
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  def create_oban_job(slug) do
    {:ok, first_datetime} =
      Twitter.MetricAdapter.first_datetime("twitter_followers", %{slug: slug})

    FollowersWorker.new(%{slug: slug, from: first_datetime})
  end
end

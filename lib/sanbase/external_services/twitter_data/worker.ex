defmodule Sanbase.ExternalServices.TwitterData.Worker do
  @moduledoc ~S"""
    A worker that regularly polls twitter for account data and stores it in
    a time series database.
  """

  @rate_limiter_name :twitter_api_rate_limiter

  use GenServer, restart: :permanent, shutdown: 5_000

  require Logger

  import Ecto.Query
  require Sanbase.Utils.Config

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.RateLimiting.Server
  alias Sanbase.ExternalServices.TwitterData.Store
  alias Sanbase.Utils.Config

  @default_update_interval 1000 * 60 * 60 * 6

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    :ok =
      ExTwitter.configure(
        consumer_key: Config.get(:consumer_key),
        consumer_secret: Config.get(:consumer_secret)
      )

    if Config.get(:sync_enabled, false) do
      Store.create_db()
      update_interval_ms = Config.get(:update_interval, @default_update_interval)

      GenServer.cast(self(), :sync)
      {:ok, %{update_interval_ms: update_interval_ms}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval_ms: update_interval_ms} = state) do
    query =
      from(
        p in Project,
        select: p.twitter_link,
        where: not is_nil(p.twitter_link)
      )

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      Repo.all(query),
      &fetch_and_store(&1),
      ordered: false,
      # IO bound
      max_concurency: System.schedulers_online() * 2,
      # twitter api time window
      timeout: 15 * 1000 * 60
    )
    |> Stream.run()

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.info("Unknown message received: #{msg}")
    {:noreply, state}
  end

  @doc ~S"""
  Stop the process from crashing on fetching fail and return nil
  """
  def fetch_twitter_user_data(twitter_name) do
    Server.wait(@rate_limiter_name)

    try do
      ExTwitter.user(twitter_name, include_entities: false)
    rescue
      _e in ExTwitter.RateLimitExceededError ->
        Logger.info("Rate limit to twitter exceeded.")
        nil

      e in ExTwitter.ConnectionError ->
        Logger.warn("Connection error while trying to fetch twitter user data: #{e.reason}")
        nil

      e in ExTwitter.Error ->
        Logger.warn("Error trying to fetch twitter user data for #{twitter_name}: #{e.message}")
        nil

      _ ->
        nil
    end
  end

  defp fetch_and_store("https://twitter.com/" <> twitter_name) do
    # Ignore trailing slash and everything after it
    twitter_name = String.split(twitter_name, "/") |> hd

    twitter_name
    |> fetch_twitter_user_data()
    |> store_twitter_user_data(twitter_name)
  end

  defp fetch_and_store(args) do
    Logger.warn("Invalid parameters while fetching twitter data: " <> inspect(args))
  end

  defp store_twitter_user_data(nil, _twitter_name), do: :ok

  defp store_twitter_user_data(twitter_user_data, twitter_name) do
    twitter_user_data
    |> convert_to_measurement(twitter_name)
    |> Store.import()
  end

  defp convert_to_measurement(
         %ExTwitter.Model.User{followers_count: followers_count},
         measurement_name
       ) do
    %Measurement{
      timestamp: DateTime.to_unix(DateTime.utc_now(), :nanosecond),
      fields: %{followers_count: followers_count},
      tags: [source: "twitter"],
      name: measurement_name
    }
  end
end
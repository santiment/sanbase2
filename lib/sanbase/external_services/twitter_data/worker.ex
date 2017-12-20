defmodule Sanbase.ExternalServices.TwitterData.Worker do
  @moduledoc ~S"""
    A worker that regularly polls twitter for account data and stores it in
    a time series database.
  """

  @rate_limiter_name :twitter_api_rate_limiter

  use GenServer, restart: :permanent, shutdown: 5_000

  require Logger

  import Ecto.Query
  import Sanbase.Utils, only: [parse_config_value: 1]

  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.RateLimiting.Server
  alias Sanbase.ExternalServices.TwitterData.{Worker, Store}

  @default_update_interval 1000 * 60 * 60 * 6

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    :ok = ExTwitter.configure(
      consumer_key: get_config(:consumer_key),
      consumer_secret: get_config(:consumer_secret),
    )

    if get_config(:sync_enabled, false) do
      Store.create_db()
      update_interval_ms = get_config(:update_interval, @default_update_interval)

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
    Logger.msg("Unknown message received: #{msg}")
    {:noreply, state}
  end

  def fetch_twitter_user_data(twitter_name) do
    Server.wait(@rate_limiter_name)
    # GET https://api.twitter.com/1.1/users/show.json?screen_name=twitter_name
    ExTwitter.user(twitter_name, include_entities: false)
  end

  defp fetch_and_store("https://twitter.com/" <> twitter_name) do
    # Ignore trailing slash and everything after it
    [twitter_name | _] = String.split(twitter_name, "/")

    twitter_name
    |> fetch_twitter_user_data()
    |> convert_to_measurement(twitter_name)
    |> store_twitter_user_data()
  end

  defp fetch_and_store(args) do
    Logger.warn("Invalid parameters while fetching twitter data: " <> inspect(args))
  end

  defp store_twitter_user_data(user_data_measurement) do
    user_data_measurement
    |> Store.import()
  end

  defp convert_to_measurement(
         %ExTwitter.Model.User{followers_count: followers_count} = user_data,
         measurement_name
       ) do
    %Measurement{
      timestamp: DateTime.to_unix(DateTime.utc_now(), :nanosecond),
      fields: twitter_data_to_fields(user_data),
      tags: [source: "twitter"],
      name: measurement_name
    }
  end

  defp twitter_data_to_fields(%ExTwitter.Model.User{followers_count: followers_count} = user_data) do
    %{followers_count: followers_count}
  end

  defp get_config(key, default \\ nil) do
    Application.fetch_env!(:sanbase, __MODULE__)
    |> Keyword.get(key, default)
    |> parse_config_value()
  end
end

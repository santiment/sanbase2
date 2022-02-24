defmodule Sanbase.Twitter.FollowersWorker do
  alias Sanbase.Twitter

  import Sanbase.DateTimeUtils,
    only: [
      generate_dates_inclusive: 2,
      date_to_datetime: 1,
      date_to_datetime: 2,
      from_iso8601!: 1
    ]

  use Oban.Worker,
    queue: :twitter_followers_migration_queue

  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project

  def queue(), do: :twitter_followers_migration_queue

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"slug" => slug, "from" => from} = args

    from = from |> from_iso8601!() |> DateTime.to_date()
    to = Timex.now() |> DateTime.to_date()

    case get_data(slug, from, to) do
      {:ok, data} ->
        export_data(slug, data)

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  # Private functions

  defp get_data(slug, from, to) do
    result =
      generate_dates_inclusive(from, to)
      |> Enum.chunk_every(30)
      |> Enum.map(fn list -> {List.first(list), List.last(list)} end)
      |> Enum.flat_map_reduce(:ok, fn {interval_from, interval_to}, acc ->
        case Twitter.MetricAdapter.timeseries_data(
               "twitter_followers",
               %{slug: slug},
               date_to_datetime(interval_from),
               date_to_datetime(interval_to, time: ~T[23:59:59.999Z]),
               "5m",
               nil
             ) do
          {:ok, nil} -> {[], acc}
          {:ok, data} -> {data, acc}
          error -> {:halt, error}
        end
      end)

    case result do
      {data, :ok} -> {:ok, data}
      {_, error} -> error
    end
  end

  def export_data(slug, data) do
    topic = Config.module_get!(Sanbase.KafkaExporter, :twitter_followers_topic)

    project = Project.by_slug(slug)

    case Project.twitter_handle(project) do
      {:ok, twitter_handle} ->
        data
        |> Enum.map(&Map.put(&1, :twitter_handle, twitter_handle))
        |> Enum.map(&Sanbase.Twitter.TimeseriesPoint.new/1)
        |> Enum.map(&Sanbase.Twitter.TimeseriesPoint.json_kv_tuple/1)
        |> Sanbase.KafkaExporter.send_data_to_topic_from_current_process(topic)

      {:error, _} ->
        :ok
    end
  end
end

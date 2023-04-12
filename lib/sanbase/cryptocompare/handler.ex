defmodule Sanbase.Cryptocompare.Handler do
  alias Sanbase.Cryptocompare.HTTPHeaderUtils
  alias Sanbase.Cryptocompare.ExporterProgress
  alias Sanbase.Utils.Config, as: Config

  @type option :: :module | :timestamps_key | :process_function | :remove_known_timestamps

  def execute_http_request(url, query_params) do
    headers = [{"authorization", "Apikey #{api_key()}"}]

    url = url <> "?" <> URI.encode_query(query_params)

    HTTPoison.get(url, headers, recv_timeout: 15_000)
  end

  def handle_http_response(http_response, opts) do
    module = Keyword.fetch!(opts, :module)
    queue = module.queue()
    timestamps_key = Keyword.fetch!(opts, :timestamps_key)
    process_function = Keyword.fetch!(opts, :process_function)

    case HTTPHeaderUtils.rate_limited?(http_response) do
      false ->
        timestamps =
          ExporterProgress.get_timestamps(
            timestamps_key,
            to_string(queue)
          )

        process_function.(http_response.body)
        |> maybe_remove_known_timestamps(timestamps, opts)

      {:error_limited, %{value: rate_limited_seconds}} ->
        do_handle_rate_limit(rate_limited_seconds, opts)
    end
  end

  # Private function
  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)

  defp maybe_remove_known_timestamps({:ok, list}, timestamps, opts) do
    # Filter out all the data points for which we already have data.
    # This works with the assumption that the data is exported in a
    # specific way. The API accepts a timestamp and a limit and returns
    # `limit` number of data points before `timestamp`. When this is done
    # a new job is scheduled with the timestamp of the earliest data point,
    # thus going back in history.

    case Keyword.get(opts, :remove_known_timestamps, false) do
      false ->
        {:ok, list}

      true ->
        list =
          case timestamps do
            nil -> list
            {min, max} -> list |> Enum.reject(&(&1.timestamp in min..max))
          end

        {:ok, list}
    end
  end

  defp maybe_remove_known_timestamps({:error, error}, _timestamps, _opts), do: {:error, error}

  defp do_handle_rate_limit(rate_limited_seconds, opts) do
    module = Keyword.fetch!(opts, :module)
    oban_conf_name = module.conf_name()
    historical_scheduler = module.historical_scheduler()
    pause_resume_worker = module.pause_resume_worker()

    :ok = historical_scheduler.pause()

    data = pause_resume_worker.new(%{"type" => "resume"}, schedule_in: rate_limited_seconds)

    Oban.insert(oban_conf_name, data)

    {:error, :rate_limit}
  end
end

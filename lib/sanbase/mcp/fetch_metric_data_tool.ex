defmodule Sanbase.MCP.FetchMetricDataTool do
  @moduledoc """
  Fetch metric timeseries for one metric and one or many slugs.

  Defaults: last 30 days (time_period="30d"), interval="1d".
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.DataCatalog

  @slugs_per_call_limit 10
  schema do
    field(:metric, :string,
      required: true,
      description: "Metric name to fetch (e.g., 'price_usd')"
    )

    field(:slugs, {:list, :string},
      required: true,
      description: """
      List of slug identifiers (e.g., ["bitcoin"], ["bitcoin", "ethereum"], etc.).

      Accepts at most #{@slugs_per_call_limit} slugs at a time.

      Only metrics that are listed as `supports_many_slugs: true` can accept a list of more than
      one slug at a time.

      The tool returns data for one metric and one or many slugs.
      """
    )

    field(:interval, :string,
      required: false,
      description: """
      The interval between two data points in the timeseries data (e.g., '5m', '1h', '1d').

      The format is: <number><suffix>, where:
      - <number> is an integer
      - <suffix> is one of:
        - m (minutes)
        - h (hours)
        - d (days)
        - w (weeks)
        - y (years)

      For example, 5m means that the data returned will have a 5 minute interval between two data points.

      Each metric has predefined `min_interval`. It describes the lowest possible interval for which data is available.
      If the metric has `min_interval=1d` it means that Santiment has one data point per day for that metric. For these
      metrics `interval="5m"` won't work as 5 minutes is less than 1 day.
      """
    )

    field(:time_period, :string,
      required: false,
      description: """
      How far back in time to fetch the data for (e.g., '7d', '30d', '90d').
      This parameter defines the range of metric data to fetch - from <time_period> time
      ago up until now.

      Defaults to 30d.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    # Note: Do it like this so we can wrap it in an if can_execute?/3 clause
    # so the execute/2 function itself is not
    do_execute(params, frame)
  end

  defp do_execute(%{metric: metric, slugs: slugs} = params, frame) do
    time_period_seconds =
      Map.get(params, :time_period, "30d") |> Sanbase.DateTimeUtils.str_to_sec()

    from = DateTime.add(DateTime.utc_now(), -time_period_seconds, :second)

    to = DateTime.utc_now()
    interval = Map.get(params, :interval, "1d")

    with :ok <- validate_metric(metric),
         :ok <- validate_slugs(slugs),
         :ok <- validate_many_slugs_supported(metric, slugs),
         {:ok, data} <- fetch_metric_data(metric, slugs, from, to, interval) do
      response_data = %{
        metric: metric,
        slugs: slugs,
        data: data,
        period: "Since #{DateTime.to_iso8601(from)}",
        interval: interval
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp validate_metric(metric) do
    if DataCatalog.valid_metric?(metric) do
      :ok
    else
      {:error, "Metric '#{metric}' mistyped or not supported."}
    end
  end

  defp validate_many_slugs_supported(_metric, [_single_slug]), do: :ok

  defp validate_many_slugs_supported(metric, slugs) when is_list(slugs) do
    case Enum.find(DataCatalog.available_metrics(), &(&1.name == metric)) do
      %{supports_many_slugs: true} ->
        :ok

      _ ->
        {:error,
         "Metric '#{metric}' does not support multiple slugs. Pass a single slug instead."}
    end
  end

  defp validate_slugs([]) do
    {:error,
     "The provided list of slugs is empty. Provide between 1 and #{@slugs_per_call_limit} slugs."}
  end

  defp validate_slugs(slugs) when is_list(slugs) and length(slugs) > @slugs_per_call_limit do
    {:error, "The list of slugs can contain at most #{@slugs_per_call_limit} slugs"}
  end

  defp validate_slugs(slugs) when is_list(slugs) do
    Enum.reduce_while(slugs, :ok, fn slug, _acc ->
      if DataCatalog.valid_slug?(slug) do
        {:cont, :ok}
      else
        {:halt, {:error, "Slug '#{slug}' mistyped or not supported."}}
      end
    end)
  end

  # Handle the case of single slug
  defp fetch_metric_data(metric, [slug], from, to, interval) do
    selector = %{slug: slug}

    case Sanbase.Metric.timeseries_data(metric, selector, from, to, interval) do
      {:ok, data} ->
        formatted_data =
          data
          |> Enum.map(fn %{datetime: datetime, value: value} ->
            %{
              datetime: DateTime.to_iso8601(datetime),
              value: value
            }
          end)

        # Return data in the format:
        # %{"ethereum" => [%{datetime: ..., value: ...}, ...]}
        # This way we can have the same format for single slug and many slugs
        {:ok, %{slug => formatted_data}}

      {:error, reason} ->
        {:error, "Failed to fetch #{metric} for #{slug}. Reason: #{reason}"}
    end
  end

  # Handle the case of many slugs
  defp fetch_metric_data(metric, [_, _ | _rest] = slugs, from, to, interval) do
    selector = %{slug: slugs}

    case Sanbase.Metric.timeseries_data_per_slug(metric, selector, from, to, interval) do
      {:ok, data} ->
        # Reshape the data so it's in the format
        #  %{
        #    "ethereum" => [%{datetime: ..., value: ...}, ...],
        #    "bitcoin" => [%{datetime: ..., value: ...}, ...]
        #  }

        formatted_data =
          data
          |> Enum.reduce(%{}, fn %{datetime: datetime, data: datapoints}, acc ->
            Enum.reduce(datapoints, acc, fn %{slug: slug, value: value}, acc_inner ->
              data_point = %{datetime: datetime, value: value}
              Map.update(acc_inner, slug, [data_point], &[data_point | &1])
            end)
          end)
          |> Map.new(fn {slug, data_points} ->
            {slug, Enum.sort_by(data_points, & &1.datetime, {:asc, DateTime})}
          end)

        {:ok, formatted_data}

      {:error, reason} ->
        {:error, "Failed to fetch #{metric} for #{Enum.join(slugs, ", ")}. Reason: #{reason}"}
    end
  end
end

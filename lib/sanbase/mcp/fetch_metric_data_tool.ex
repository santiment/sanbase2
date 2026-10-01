defmodule Sanbase.MCP.FetchMetricDataTool do
  @moduledoc """
  Fetch metric timeseries for one metric and one or many slugs.

  Defaults: last 30 days (time_period="30d"), interval="1d".

  Use this when the assets are already known and the values over time matter.
  For the opposite direction — "which assets satisfy X" / "top N by X", one
  aggregated value per asset across the whole universe — use
  `assets_by_metric_tool`. To confirm a metric exists for a slug first, use
  `metrics_and_assets_discovery_tool`; to draw the result, use `show_chart`.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.{DataCatalog, ToolError, Utils}

  @impl true
  def annotations do
    %{
      "title" => "Fetch Metric Data",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  @slugs_per_call_limit 10
  @max_total_datapoints 1000

  # Social data keeps arriving after a bucket is first published, so the newest
  # buckets are preliminary. Ratio metrics like social dominance are hit hardest:
  # the denominator (the combined volume of the top 100 assets) fills in later
  # than the asset's own volume, so a fresh bucket can read 100% and then settle.
  @preliminary_window_hours 2
  @revision_window_hours 12
  @social_metric_prefixes ["social_volume_", "social_dominance_", "sentiment_"]

  schema do
    field(:metric, :string,
      required: true,
      description: """
      Metric name to fetch (e.g., 'price_usd').

      IMPORTANT: Before fetching data, verify metric names by calling the
      metrics_and_assets_discovery_tool first. Only metrics listed there are supported.
      Do not guess or infer metric names — they may differ from what you expect.
      """
    )

    field(:slugs, {:list, :string},
      required: true,
      description: """
      List of slug identifiers (e.g., ["bitcoin"], ["bitcoin", "ethereum"], etc.).

      Accepts at most #{@slugs_per_call_limit} slugs at a time.

      Only metrics that have `supports_many_slugs: true` can accept more than one slug.
      Check the `supports_many_slugs` field in the metrics_and_assets_discovery_tool response
      before passing multiple slugs. Financial and on-chain metrics generally support multiple
      slugs; social, sentiment, and derivatives metrics generally do not.

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
    time_period = Map.get(params, :time_period, "30d")
    interval = Map.get(params, :interval, "1d")

    with :ok <- validate_metric(metric),
         :ok <- validate_slugs(slugs),
         :ok <- validate_many_slugs_supported(metric, slugs),
         {:ok, {from, to}} <- Utils.parse_time_period(time_period),
         {:ok, data} <- fetch_metric_data(metric, slugs, from, to, interval) do
      {data, limited} = limit_datapoints(data)
      preliminary_since = preliminary_since(metric, data, interval, to)

      response_data =
        %{
          metric: metric,
          slugs: slugs,
          data: data,
          period: "Since #{DateTime.to_iso8601(from)}",
          interval: interval
        }
        |> maybe_add_limit_notice(limited)
        |> maybe_add_preliminary_notice(metric, preliminary_since)
        |> Utils.truncate_response()

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp limit_datapoints(data) do
    total = data |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

    if total <= @max_total_datapoints do
      {data, false}
    else
      per_slug = max(div(@max_total_datapoints, map_size(data)), 1)

      limited_data =
        Map.new(data, fn {slug, points} -> {slug, Enum.take(points, -per_slug)} end)

      {limited_data, true}
    end
  end

  defp maybe_add_limit_notice(data, false), do: data

  defp maybe_add_limit_notice(data, true) do
    Map.put(
      data,
      :notice,
      "Datapoints limited to #{@max_total_datapoints} total (most recent kept). Use a coarser interval or shorter time_period for complete data."
    )
  end

  # Returns the datetime of the first datapoint whose bucket overlaps the
  # preliminary window, or nil when the metric is not social or no such point exists.
  defp preliminary_since(metric, data, interval, now) do
    if String.starts_with?(metric, @social_metric_prefixes) do
      cutoff =
        now
        |> DateTime.add(-@preliminary_window_hours * 3600, :second)
        |> DateTime.add(-Sanbase.Utils.DateTime.str_to_sec(interval), :second)

      data
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&Sanbase.Utils.DateTime.from_iso8601!(&1.datetime))
      |> Enum.filter(&(DateTime.compare(&1, cutoff) == :gt))
      |> Enum.min(DateTime, fn -> nil end)
    end
  end

  defp maybe_add_preliminary_notice(data, _metric, nil), do: data

  defp maybe_add_preliminary_notice(data, metric, %DateTime{} = since) do
    notice =
      "Datapoints from #{DateTime.to_iso8601(since)} onward are preliminary: social data " <>
        "for the last #{@preliminary_window_hours} hours is still arriving, and social " <>
        "data can be revised for up to #{@revision_window_hours} hours. Do not treat a move " <>
        "inside this window as a signal on its own. If a later fetch returns different " <>
        "values for these datapoints, the data was revised."

    notice =
      if String.starts_with?(metric, "social_dominance_") do
        notice <>
          " Social dominance divides the asset's social volume by the combined social volume " <>
          "of the 100 largest assets by market cap. While the other assets' volumes are still " <>
          "arriving the denominator is too small, so recent dominance can spike sharply (even " <>
          "to 100%) and settle later. Before reporting a dominance spike in this window, check " <>
          "social_volume_total for the same asset: if its volume did not rise too, the spike " <>
          "is most likely incomplete data."
      else
        notice
      end

    Map.put(data, :preliminary_data_notice, notice)
  end

  # Validation failures are tagged [permanent] (ToolError): the same arguments can
  # never succeed, so agent clients fix the arguments or move on instead of retrying.
  defp validate_metric(metric) do
    if DataCatalog.valid_metric?(metric) do
      :ok
    else
      {:error, ToolError.permanent(DataCatalog.metric_not_found_error(metric))}
    end
  end

  defp validate_many_slugs_supported(_metric, [_single_slug]), do: :ok

  defp validate_many_slugs_supported(metric, slugs) when is_list(slugs) do
    case Enum.find(DataCatalog.available_metrics(), &(&1.name == metric)) do
      %{supports_many_slugs: true} ->
        :ok

      _ ->
        {:error,
         ToolError.permanent(
           "Metric '#{metric}' does not support multiple slugs. Pass a single slug instead."
         )}
    end
  end

  defp validate_slugs([]) do
    {:error,
     ToolError.permanent(
       "The provided list of slugs is empty. Provide between 1 and #{@slugs_per_call_limit} slugs."
     )}
  end

  defp validate_slugs(slugs) when is_list(slugs) and length(slugs) > @slugs_per_call_limit do
    {:error,
     ToolError.permanent("The list of slugs can contain at most #{@slugs_per_call_limit} slugs")}
  end

  defp validate_slugs(slugs) when is_list(slugs) do
    Enum.reduce_while(slugs, :ok, fn slug, _acc ->
      if DataCatalog.valid_slug?(slug) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          ToolError.permanent(
            "Slug '#{slug}' mistyped or not supported. Use the " <>
              "metrics_and_assets_discovery_tool to resolve valid asset slugs."
          )}}
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

defmodule Sanbase.MCP.ShowChartTool do
  @moduledoc """
  Render a Santiment chart with an asset's price (OHLC) plus an optional
  overlay metric in a second pane. The widget that consumes this tool is
  built on the Santiment chart library (lightweight-charts under the hood),
  so the response is render-ready — the client just feeds each `series`
  entry into the chart unchanged.

  ## Parameters

  - `slug` — asset slug (e.g. `bitcoin`, `ethereum`). Defaults to `bitcoin`.
  - `primary` — what goes into the main pane.
    - `"price"` (default) — OHLC candlestick.
    - any metric name from the catalog — line/area instead of candles.
  - `overlay` — optional metric name to render in a second pane.
    Allowed values are listed below.
  - `range` — `24h`, `7d`, `30d`, `90d`, `1y`. Defaults to `30d`.

  ## Available overlay metrics (catalog)

  social_volume_total, social_dominance_total, sentiment_balance_total,
  sentiment_weighted_total, daily_active_addresses, network_growth,
  transaction_volume_usd, velocity, mvrv_usd, nvt, realized_value_usd,
  mvrv_long_short_diff_usd, exchange_balance,
  whale_transaction_count_100k_usd_to_inf, top_holders_held_supply_percent,
  dev_activity, github_activity, volume_usd, marketcap_usd,
  funding_rate_perp.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.ChartMetricCatalog

  @default_slug "bitcoin"
  @default_range "30d"
  @valid_ranges ~w(24h 7d 30d 90d 1y)

  # Override Anubis's default module-derived name (would be "show_chart_tool").
  def name, do: "show_chart"

  @impl true
  def annotations do
    %{
      "title" => "Show Chart",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  @impl true
  def meta do
    %{"ui" => %{"resourceUri" => Sanbase.MCP.ChartUI.current_uri()}}
  end

  schema do
    field(:slug, :string,
      required: false,
      description: "Asset slug (e.g. 'bitcoin', 'ethereum'). Defaults to 'bitcoin'."
    )

    field(:primary, :string,
      required: false,
      description:
        "Primary series — 'price' for candlestick OHLC, or a metric name from the catalog. Defaults to 'price'."
    )

    field(:overlay, :string,
      required: false,
      description:
        "Optional metric to overlay in a second pane. Must be one of the catalog names (see tool description)."
    )

    field(:range, :string,
      required: false,
      description: "Time range. One of: 24h, 7d, 30d, 90d, 1y. Defaults to 30d."
    )
  end

  @impl true
  def execute(params, frame) do
    slug = params[:slug] || @default_slug
    range = params[:range] || @default_range
    primary = params[:primary] || ChartMetricCatalog.price_primary()
    overlay = params[:overlay]

    with :ok <- validate_range(range),
         :ok <- validate_metric(primary, :primary),
         :ok <- validate_metric(overlay, :overlay) do
      {from, to, interval} = window_for(range)

      # Primary and overlay are independent fetches — run them concurrently.
      [primary_result, overlay_result] =
        [
          fn -> build_primary(primary, slug, from, to, interval) end,
          fn -> build_overlay(overlay, slug, from, to, interval) end
        ]
        |> Task.async_stream(& &1.(), timeout: 30_000, on_timeout: :kill_task, ordered: true)
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, :timeout} -> {:error, "data fetch timed out"}
          {:exit, reason} -> {:error, "data fetch failed: #{inspect(reason)}"}
        end)

      case primary_result do
        {:ok, primary_series} ->
          # Overlay is best-effort — if it fails (e.g. missing service in dev
          # or metric doesn't apply to the asset), we still render the primary.
          {overlay_series, overlay_warning} =
            case overlay_result do
              {:ok, series} -> {series, nil}
              {:error, reason} -> {nil, reason}
            end

          series = [primary_series | overlay_to_list(overlay_series)]

          response_data =
            %{
              slug: slug,
              range: range,
              interval: interval,
              period_start: DateTime.to_iso8601(from),
              period_end: DateTime.to_iso8601(to),
              summary: build_summary(primary_series, overlay_series),
              series: series
            }
            |> maybe_put_warning(overlay_warning)

          {:reply, Response.structured(Response.tool(), response_data), frame}

        {:error, reason} ->
          {:reply, Response.error(Response.tool(), reason), frame}
      end
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp maybe_put_warning(data, nil), do: data
  defp maybe_put_warning(data, warning), do: Map.put(data, :warning, warning)

  # ── Validation ────────────────────────────────────────────────────────────

  defp validate_range(range) when range in @valid_ranges, do: :ok

  defp validate_range(range),
    do: {:error, "Invalid range '#{range}'. Use one of: #{Enum.join(@valid_ranges, ", ")}."}

  defp validate_metric(nil, _role), do: :ok
  defp validate_metric("", _role), do: :ok

  defp validate_metric(name, :primary) do
    if ChartMetricCatalog.price_primary?(name) or name in ChartMetricCatalog.names() do
      :ok
    else
      {:error,
       "Unknown primary metric '#{name}'. Use 'price' or one of: #{Enum.join(ChartMetricCatalog.names(), ", ")}."}
    end
  end

  defp validate_metric(name, :overlay) do
    if name in ChartMetricCatalog.names() do
      :ok
    else
      {:error,
       "Unknown overlay metric '#{name}'. Use one of: #{Enum.join(ChartMetricCatalog.names(), ", ")}."}
    end
  end

  # ── Window ────────────────────────────────────────────────────────────────

  defp window_for(range) do
    {seconds, interval} =
      case range do
        "24h" -> {86_400, "1h"}
        "7d" -> {7 * 86_400, "1h"}
        "30d" -> {30 * 86_400, "4h"}
        "90d" -> {90 * 86_400, "1d"}
        "1y" -> {365 * 86_400, "1d"}
      end

    to = DateTime.utc_now()
    from = DateTime.add(to, -seconds, :second)
    {from, to, interval}
  end

  # ── Primary (price OHLC | metric line) ───────────────────────────────────

  defp build_primary(primary, slug, from, to, interval) do
    if ChartMetricCatalog.price_primary?(primary) do
      build_price_ohlc(slug, from, to, interval)
    else
      build_metric_line(primary, slug, from, to, interval, pane_override: 0)
    end
  end

  defp build_price_ohlc(slug, from, to, interval) do
    catalog = ChartMetricCatalog.fetch!("price_usd")

    case Sanbase.Price.timeseries_ohlc_data(slug, from, to, interval) do
      {:ok, candles} ->
        data =
          Enum.map(candles, fn %{
                                 datetime: dt,
                                 open_price_usd: o,
                                 high_price_usd: h,
                                 low_price_usd: l,
                                 close_price_usd: c
                               } ->
            %{
              time: DateTime.to_unix(dt),
              open: round_num(o),
              high: round_num(h),
              low: round_num(l),
              close: round_num(c)
            }
          end)

        {:ok,
         %{
           id: "primary",
           name: catalog.name,
           label: catalog.label,
           style: Atom.to_string(catalog.style),
           color: catalog.color,
           pane: 0,
           unit: catalog.unit,
           data: data
         }}

      {:error, reason} ->
        {:error, "Failed to fetch OHLC for #{slug}: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Failed to fetch OHLC for #{slug}: #{Exception.message(e)}"}
  end

  # ── Overlay (catalog metric line/area/histogram) ─────────────────────────

  defp build_overlay(nil, _slug, _from, _to, _interval), do: {:ok, nil}
  defp build_overlay("", _slug, _from, _to, _interval), do: {:ok, nil}

  defp build_overlay(metric_name, slug, from, to, interval) do
    build_metric_line(metric_name, slug, from, to, interval, role: :overlay)
  end

  defp overlay_to_list(nil), do: []
  defp overlay_to_list(series), do: [series]

  defp build_metric_line(metric_name, slug, from, to, interval, opts) do
    catalog = ChartMetricCatalog.fetch!(metric_name)
    pane = Keyword.get(opts, :pane_override, catalog.default_pane)
    role = Keyword.get(opts, :role, :primary)
    id = if role == :overlay, do: "overlay", else: "primary"
    # Daily-only metrics (mvrv, nvt, …) error when queried below their
    # min_interval, so never request finer than the metric supports.
    interval = effective_interval(metric_name, interval)

    case Sanbase.Metric.timeseries_data(metric_name, %{slug: slug}, from, to, interval) do
      {:ok, points} ->
        data =
          Enum.map(points, fn %{datetime: dt, value: v} ->
            %{time: DateTime.to_unix(dt), value: round_num(v)}
          end)

        {:ok,
         %{
           id: id,
           name: catalog.name,
           label: catalog.label,
           style: Atom.to_string(catalog.style),
           color: catalog.color,
           pane: pane,
           unit: catalog.unit,
           data: data
         }}

      {:error, reason} ->
        {:error, "Failed to fetch #{metric_name} for #{slug}: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Failed to fetch #{metric_name} for #{slug}: #{Exception.message(e)}"}
  end

  # ── Summary ──────────────────────────────────────────────────────────────

  defp build_summary(primary_series, overlay_series) do
    %{
      primary: series_summary(primary_series),
      overlay: if(overlay_series, do: series_summary(overlay_series), else: nil)
    }
  end

  defp series_summary(%{data: []} = s),
    do: %{label: s.label, unit: s.unit, current: nil, change_pct: 0.0}

  defp series_summary(%{data: data, label: label, unit: unit}) do
    first = List.first(data)
    last = List.last(data)

    {first_val, last_val} = {value_of(first), value_of(last)}

    %{
      label: label,
      unit: unit,
      current: last_val,
      change_pct: pct_change(first_val, last_val)
    }
  end

  defp value_of(%{close: c}), do: c
  defp value_of(%{value: v}), do: v
  defp value_of(_), do: nil

  defp pct_change(from, to)
       when is_number(from) and is_number(to) and from != 0 do
    Float.round((to - from) / from * 100, 2)
  end

  defp pct_change(_, _), do: 0.0

  # Magnitude-aware rounding: 2 decimals for normal values, but keep precision
  # for sub-cent assets (e.g. SHIB) so candles don't collapse to 0.0.
  defp round_num(nil), do: nil

  defp round_num(n) when is_number(n) do
    digits =
      case Kernel.abs(n / 1) do
        a when a >= 1.0 -> 2
        a when a >= 0.01 -> 4
        _ -> 8
      end

    Float.round(n / 1, digits)
  end

  # Never request a finer interval than the metric supports (its min_interval),
  # otherwise the metric fetch errors. Falls back to the requested interval.
  defp effective_interval(metric_name, interval) do
    case Sanbase.Metric.metadata(metric_name) do
      {:ok, %{min_interval: min}} when is_binary(min) -> coarser_interval(interval, min)
      _ -> interval
    end
  end

  defp coarser_interval(requested, min) do
    case {safe_sec(requested), safe_sec(min)} do
      {req, mn} when is_integer(req) and is_integer(mn) -> if req >= mn, do: requested, else: min
      _ -> requested
    end
  end

  defp safe_sec(interval) do
    Sanbase.Utils.DateTime.str_to_sec(interval)
  rescue
    _ -> nil
  end
end

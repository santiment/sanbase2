defmodule Sanbase.Chart do
  @moduledoc ~s"""
  Builds an image and stores it in S3
  """

  alias Sanbase.Model.Project
  alias Sanbase.FileStore
  alias Sanbase.Math

  require Logger
  require Mockery.Macro

  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)

  @spec build_embedded_chart(%Project{}, %DateTime{}, %DateTime{}, list()) :: [
          %{image: %{url: String.t()}}
        ]
  def build_embedded_chart(%Project{slug: slug} = project, from, to, opts \\ []) do
    with {:ok, url} <- build_candlestick_image_url(project, from, to, opts),
         {:ok, resp} <- http_client().get(url),
         {:ok, filename} <-
           FileStore.store(%{filename: rand_image_filename(slug), binary: resp.body}),
         url <- FileStore.url(filename) do
      [%{image: %{url: url}}]
    else
      _ -> []
    end
  end

  # Build candlestick image url using google charts API. Inspect the `:chart_type`
  # value from `opts` and add an overlaying chart that represents a specific metric.
  # Currently supported such metrics are `:daily_active_addresses` and `:exchange_inflow`
  defp build_candlestick_image_url(
         %Project{slug: slug} = project,
         from,
         to,
         opts
       ) do
    with {:ok, ohlc} when is_list(ohlc) and ohlc != [] <-
           Sanbase.Price.timeseries_ohlc_data(slug, from, to, "1d"),
         {:ok, prices} <- candlestick_prices(ohlc),
         {:ok, image} <- generate_image_url(project, prices, from, to, opts) do
      {:ok, image}
    else
      error ->
        Logger.error(
          "Error building image for #{Project.describe(project)}. Reason: #{inspect(error)}"
        )

        {:error, "Error building image for #{Project.describe(project)}"}
    end
  end

  # Private functions

  defp generate_image_url(project, prices, from, to, opts) do
    [_open, high_values, _close, low_values] = prices
    min = low_values |> Enum.min() |> Float.floor(6)
    max = high_values |> Enum.max() |> Float.ceil(6)

    [open_str, high_str, close_str, low_str] = prices |> Enum.map(&Enum.join(&1, ","))

    size = Enum.count(low_values)

    line_chart = build_line_chart(project, from, to, size, opts)

    bar_width = if size > 20, do: 6 * round(90 / size), else: 23

    {:ok, ~s(
        https://chart.googleapis.com/chart?
        cht=lc&
        chs=800x200&
        chtt=#{line_chart.chtt}&
        chxt=y#{line_chart.chxt}&
        chxl=#{line_chart.chxl}&
        chxr=0,#{min},#{max}#{line_chart.chxr}&
        chds=#{line_chart.chds}#{min},#{max}&
        chxs=0N*cUSDf6*#{line_chart.chxs}&
        chd=#{line_chart.chd}|#{low_str}|#{open_str}|#{close_str}|#{high_str}&
        chm=F,,1,1:#{size},#{bar_width}&
        chma=10,20,20,10&
        &chco=00FF00
      ) |> String.replace(~r/[\n\s+]+/, "")}
  end

  # Returns a list of 4 lists. Each list contains the list of open, high, low
  # and close price respectively
  defp candlestick_prices(ohlc) do
    prices =
      Enum.map(
        ohlc,
        fn %{
             open_price_usd: open,
             close_price_usd: close,
             high_price_usd: high,
             low_price_usd: low
           } ->
          [
            open |> Math.to_float(0.0) |> Float.round(6),
            high |> Math.to_float(0.0) |> Float.round(6),
            close |> Math.to_float(0.0) |> Float.round(6),
            low |> Math.to_float(0.0) |> Float.round(6)
          ]
        end
      )
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)

    {:ok, prices}
  end

  defp build_line_chart(project, from, to, size, opts) do
    case Keyword.get(opts, :chart_type) do
      :volume ->
        chart_values(:volume, project, from, to, size)

      {:metric, _} = metric ->
        chart_values(metric, project, from, to, size)

      _ ->
        empty_values(from, to)
    end
  end

  defp chart_values(:volume, %Project{} = project, _from, to, size) do
    from = Timex.shift(to, days: -size + 1)

    with {:ok, data} <- Sanbase.Price.timeseries_data(project.slug, from, to, "1d"),
         [_ | _] = volumes <- data |> Enum.map(& &1.volume_usd),
         {min, max} <- Math.min_max(volumes) do
      volumes_str = volumes |> Enum.join(",")

      %{
        chtt: "#{project.name} - Trading Volume and OHLC Price" |> URI.encode(),
        chxt: ",x,r",
        chxl: "1:|#{datetime_values(from, to)}" |> URI.encode(),
        chxr: "|2,#{min},#{max}",
        chxs: "|2N*cUSDs*",
        chds: "#{min},#{max},",
        chd: "t1:#{volumes_str}"
      }
    else
      {:error, error} ->
        Logger.error(
          "Cannot fetch volume for #{Project.describe(project)}. Reason: #{inspect(error)}"
        )

        empty_values(from, to)

      _ ->
        empty_values(from, to)
    end
  end

  defp chart_values({:metric, metric}, %Project{} = project, _from, to, size) do
    %Project{slug: slug, name: name} = project
    from = Timex.shift(to, days: -size + 1)

    with {:ok, metric_name} <- Sanbase.Metric.human_readable_name(metric),
         {:ok, data} <- Sanbase.Metric.timeseries_data(metric, %{slug: slug}, from, to, "1d"),
         [_ | _] = values <- data |> Enum.map(& &1.value) |> Enum.reject(&is_nil/1),
         {min, max} <- Math.min_max(values) do
      %{
        chtt: "#{name} - #{metric_name} and OHLC Price" |> URI.encode(),
        chxt: ",x,r",
        chxl: "1:|#{datetime_values(from, to)}" |> URI.encode(),
        chxr: "|2,#{min},#{max}",
        chds: "#{min},#{max},",
        chd: "t1:#{values |> Enum.join(",")}",
        chxs: ""
      }
    else
      {:error, error} ->
        Logger.error(
          "Cannot fetch #{metric} for #{Project.describe(project)}. Reason: #{inspect(error)}"
        )

        empty_values(from, to)

      _ ->
        empty_values(from, to)
    end
  end

  # Generate a list of `|` separated values, used as the value for `chxl` in the chart
  # Return a list of 10 datetimes in the format `Oct 15`. The last datetime is manually added
  # so it coincides with the `to` parameter. That is because if the difference `to-from` is
  # not evenly divisible by 10 then the last datetime will be different
  defp datetime_values(from, to) do
    diff = Timex.diff(from, to, :days) |> abs()
    interval = div(diff, 10)

    datetimes =
      for i <- 1..9 do
        Timex.format!(Timex.shift(from, days: interval * i), "%b %d", :strftime)
      end

    (datetimes ++ [Timex.format!(to, "%b %d", :strftime)])
    |> Enum.join("|")
  end

  defp empty_values(from, to) do
    %{
      chxt: ",x",
      chxr: "",
      chds: "",
      chd: "t0:1",
      chxs: "",
      chtt: "",
      chxl: "1:|#{datetime_values(from, to)}" |> URI.encode()
    }
  end

  # Private functions

  defp rand_image_filename(slug) do
    random_string = :crypto.strong_rand_bytes(20) |> Base.encode32()
    slug <> random_string <> ".png"
  end
end

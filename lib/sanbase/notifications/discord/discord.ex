defmodule Sanbase.Notifications.Discord do
  @moduledoc ~s"""
  Send notification to Discord and handle the response
  """
  require Mockery.Macro
  require Logger

  alias Sanbase.Prices.Store, as: PricesStore
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project
  alias Sanbase.Blockchain.{DailyActiveAddresses, ExchangeFundsFlow}
  alias Sanbase.FileStore
  alias Sanbase.Utils.Math

  @discord_message_size_limit 1900

  @type json :: String.t()

  @doc ~s"""
  Send the payload to Discord. Handle the response and log accordingly
  """
  @spec send_notification(String.t(), String.t(), json, map()) :: :ok | {:error, String.t()}
  def send_notification(_, _, _, opts \\ %{})

  def send_notification(_, _, _, %{retry_count: 5}), do: {:error, "Max retries reached"}

  def send_notification(webhook, signal_name, payload, opts) do
    case http_client().post(webhook, payload, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{status_code: code}} when code in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{status_code: 429, body: body} = resp} ->
        body = body |> Jason.decode!()

        Logger.info(
          "Cannot publish #{signal_name} signal in Discord: HTTP Response: #{inspect(resp)}"
        )

        Process.sleep(body["retry_after"] + 1000)

        send_notification(
          webhook,
          signal_name,
          payload,
          Map.update(opts, :retry_count, 0, &(&1 + 1))
        )

      {:ok, %HTTPoison.Response{} = resp} ->
        Logger.error(
          "Cannot publish #{signal_name} signal in Discord: HTTP Response: #{inspect(resp)}"
        )

        {:error, "Cannot publish #{signal_name} signal in Discord"}

      {:error, error} ->
        Logger.error("Cannot publish #{signal_name} in Discord. Reason: " <> inspect(error))
        {:error, "Cannot publish #{signal_name} signal in Discord"}
    end
  end

  @doc ~s"""
  Encode the payload and the username that will be used as the author of the Disord message.
  The result is ready to be passed to `send_notification/3`
  """
  @spec encode!([String.t()], String.t()) :: String.t() | no_return
  def encode!([], _), do: nil

  def encode!(payload, publish_user) do
    payload =
      payload
      |> Enum.join("\n")

    Jason.encode!(%{content: payload, username: publish_user})
  end

  @doc ~s"""
  Encode the string payload, username and list of embeds.
  The result is ready to be passed to `send_notification/3`
  """
  @spec encode!(String.t(), String.t(), [any()]) :: String.t()
  def encode!(payload, publish_user, embeds) do
    Jason.encode!(%{content: payload, username: publish_user, embeds: embeds})
  end

  @doc ~s"""
  Builds discord embeds object with chart URL for a given project slug and time interval
  """
  @spec build_embedded_chart(String.t(), %DateTime{}, %DateTime{}, list()) :: [
          %{image: %{url: String.t()}}
        ]
  def build_embedded_chart(%Project{coinmarketcap_id: slug} = project, from, to, opts \\ []) do
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

  @doc ~s"""
  Build candlestick image url using google charts API. Inspect the `:chart_type`
  value from `opts` and add an overlaying chart that represents a specific metric.
  Currently supported such metrics are `:daily_active_addresses` and `:exchange_inflow`
  """
  @spec build_candlestick_image_url(String.t(), %DateTime{}, %DateTime{}, list()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp build_candlestick_image_url(
         %Project{coinmarketcap_id: slug} = project,
         from,
         to,
         opts \\ []
       ) do
    with measurement when not is_nil(measurement) <- Measurement.name_from_slug(slug),
         {:ok, ohlc} when is_list(ohlc) <- PricesStore.fetch_ohlc(measurement, from, to, "1d"),
         number when number != 0 <- length(ohlc),
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
    [_open, high_values, low_values, _close, _avg] = prices
    min = low_values |> Enum.min() |> Float.floor(2)
    max = high_values |> Enum.max() |> Float.ceil(2)

    [open_str, high_str, low_str, close_str, _average_str] =
      prices |> Enum.map(&Enum.join(&1, ","))

    size = Enum.count(low_values)

    line_chart = build_line_chart(project, from, to, size, opts)

    bar_width = if size > 20, do: 6 * round(90 / size), else: 23

    {:ok, ~s(
        https://chart.googleapis.com/chart?
        cht=lc&
        chs=800x200&
        chxt=y#{line_chart.chxt}&
        chxr=0,#{min},#{max}#{line_chart.chxr}&
        chds=#{line_chart.chds}#{min},#{max}&
        chxs=#{line_chart.chxs}&
        chd=#{line_chart.chd}|#{low_str}|#{open_str}|#{close_str}|#{high_str}&
        chm=F,,1,1:#{size},#{bar_width}&
        chma=10,20,20,10&
        &chco=00FF00
      ) |> String.replace(~r/[\n\s+]+/, "")}
  end

  defp candlestick_prices(ohlc) do
    [_ | prices] =
      ohlc
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)

    prices =
      prices
      |> Enum.map(fn list -> list |> Enum.filter(&(&1 != 0)) end)
      |> Enum.map(fn list ->
        list
        |> Enum.map(&Math.to_float/1)
        |> Enum.map(fn num ->
          if num > 1 do
            Float.round(num, 2)
          else
            Float.round(num, 6)
          end
        end)
      end)

    {:ok, prices}
  end

  defp build_line_chart(project, from, to, size, opts) do
    case Keyword.get(opts, :chart_type) do
      :daily_active_addresses ->
        daa_chart_values(project, from, to, size)

      :exchange_inflow ->
        exchange_inflow_chart_values(project, from, to, size)

      _ ->
        empty_values()
    end
  end

  defp daa_chart_values(%Project{} = project, _from, to, size) do
    from = Timex.shift(to, days: -size + 1)

    with {:ok, contract, _} <- Project.contract_info(project),
         {:ok, daa} <- DailyActiveAddresses.active_addresses(contract, from, to, "1d") do
      daa_values = daa |> Enum.map(fn %{active_addresses: value} -> value end)
      max = daa_values |> Enum.max()
      min = daa_values |> Enum.min()

      daa_values = daa_values |> Enum.join(",")

      %{
        chxt: ",r",
        chxr: "|1,#{min},#{max}",
        chds: "#{min},#{max},",
        chd: "t1:#{daa_values}",
        chxs: ""
      }
    else
      error ->
        Logger.error(
          "Cannot fetch Daily Active Addresses for #{Project.describe(project)}. Reason: #{
            inspect(error)
          }"
        )

        empty_values()
    end
  end

  defp exchange_inflow_chart_values(%Project{} = project, _from, to, size) do
    from = Timex.shift(to, days: -size + 1)

    with {:ok, contract, token_decimals} <- Project.contract_info(project),
         {:ok, exchange_inflow} <-
           ExchangeFundsFlow.transactions_in_over_time(contract, from, to, "1d", token_decimals),
         supply when not is_nil(supply) <- Project.supply(project) do
      exchange_inflow_values =
        exchange_inflow |> Enum.map(fn %{inflow: value} -> value / supply end)

      max = exchange_inflow_values |> Enum.max()
      min = exchange_inflow_values |> Enum.min()

      exchange_inflow_values = exchange_inflow_values |> Enum.join(",")

      %{
        chxt: ",r",
        chxr: "|1,#{min},#{max}",
        chxs: "1N*p2*",
        chds: "#{min},#{max},",
        chd: "t1:#{exchange_inflow_values}"
      }
    else
      error ->
        Logger.error(
          "Cannot fetch Exchange Inflow for #{Project.describe(project)}. Reason: #{
            inspect(error)
          }"
        )

        empty_values()
    end
  end

  defp empty_values() do
    %{chxt: "", chxr: "", chds: "", chd: "t0:1", chxs: ""}
  end

  defp http_client() do
    Mockery.Macro.mockable(HTTPoison)
  end

  defp messages_len([]), do: 0
  defp messages_len(str) when is_binary(str), do: String.length(str)

  defp messages_len(list) when is_list(list) do
    list
    |> Enum.map(&String.length/1)
    |> Enum.sum()
  end

  defp rand_image_filename(slug) do
    random_string = :crypto.strong_rand_bytes(20) |> Base.encode32()
    slug <> random_string <> ".png"
  end
end

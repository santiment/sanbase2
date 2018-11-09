defmodule Sanbase.Notifications.Discord do
  @moduledoc ~s"""
  Send notification to Discord and handle the response
  """
  require Mockery.Macro
  require Logger

  alias Sanbase.Prices.Store, as: PricesStore
  alias Sanbase.Influxdb.Measurement

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
  Discord currently has limit of 2000 chars.
  Groups a list of messages into groups which combined doesn't exceed `message_size_limit`
  """
  @spec group_messages([any()]) :: [any()]
  def group_messages(messages) do
    {groups, last} =
      messages
      |> Enum.reduce({[], []}, fn el, {acc, tmp_acc} ->
        if messages_len(el) + messages_len(tmp_acc) > @discord_message_size_limit do
          {acc ++ [tmp_acc], [el]}
        else
          {acc, tmp_acc ++ [el]}
        end
      end)

    groups ++ [last]
  end

  @doc ~s"""
  Builds discord embeds object for a given project slug and time interval
  """
  @spec build_embeds(String.t(), any(), any()) :: [any()]
  def build_embeds(slug, from, to) do
    case build_candlestick_image_url(slug, from, to) do
      {:ok, url} -> [%{image: %{url: url}}]
      {:error, _} -> []
    end
  end

  @doc ~s"""
  Build candlestick image url using google charts api
  """
  def build_candlestick_image_url(slug, from, to) do
    with measurement when not is_nil(measurement) <- Measurement.name_from_slug(slug),
         {:ok, ohlc} when is_list(ohlc) <- PricesStore.fetch_ohlc(measurement, from, to, "1d"),
         6 <- hd(ohlc) |> length() do
      ohlc =
        ohlc
        |> Enum.zip()
        |> Enum.map(&Tuple.to_list/1)

      [datetimes | prices] = ohlc

      [_, high_values, low_values, _, _] = prices
      min = Enum.min(low_values) |> Float.floor(2)
      max = Enum.max(high_values) |> Float.ceil(2)

      [open, high, low, close, avg] =
        prices
        |> Enum.map(fn list -> list |> Enum.map(&Float.round(&1, 6)) end)
        |> Enum.map(fn list -> Enum.join(list, ",") end)

      days_str =
        datetimes
        |> Enum.map(fn datetime -> datetime |> DateTime.to_date() |> Map.get(:day) end)
        |> Enum.join("|")

      size = datetimes |> Enum.count()

      {:ok, ~s(
        https://chart.googleapis.com/chart?
        cht=lc&
        chs=800x200&
        chxt=x,y&
        chxr=1,#{min},#{max}&
        chxl=0:|#{days_str}&
        chd=t1:#{avg}|#{low}|#{open}|#{close}|#{high}&
        chds=#{min},#{max}&
        chm=F,,1,1:#{size},20
      ) |> String.replace(~r/[\n\s+]+/, "")}
    else
      error ->
        Logger.error("Error building image for slug: #{slug}: #{inspect(error)}")
        {:error, "Error building image for slug: #{slug}"}
    end
  end

  # Private functions
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
end

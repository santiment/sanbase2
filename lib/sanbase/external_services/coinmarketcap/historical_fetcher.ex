defmodule Sanbase.ExternalServices.Coinmarketcap.HistoricalFetcher do
  @moduledoc ~s"""
  Fetches historical CMC ticker data for a range of timestamps.

  Given from/to datetimes and an interval (in seconds), fires one
  TickerFetcher.work/1 request per timestamp in the range.

  ## Usage

      # Backfill the last 15 hours with 5-minute intervals:
      from = DateTime.utc_now() |> DateTime.add(-15 * 3600)
      to = DateTime.utc_now()
      Sanbase.ExternalServices.Coinmarketcap.HistoricalFetcher.run(from, to, 300)

      # With custom options (projects_number, sleep between requests):
      Sanbase.ExternalServices.Coinmarketcap.HistoricalFetcher.run(
        from, to, 300,
        projects_number: 5000,
        sleep_between_requests_ms: 3000
      )
  """

  require Logger

  alias Sanbase.ExternalServices.Coinmarketcap.TickerFetcher

  @default_sleep_ms 2_000

  @doc """
  Fetches historical data for each timestamp in the range [from, to]
  spaced `interval_seconds` apart.

  Options:
    - `:projects_number` - number of top projects to fetch (default from config)
    - `:sleep_between_requests_ms` - milliseconds to sleep between requests (default #{@default_sleep_ms})
  """
  @spec run(DateTime.t(), DateTime.t(), pos_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  def run(%DateTime{} = from, %DateTime{} = to, interval_seconds, opts \\ [])
      when is_integer(interval_seconds) and interval_seconds > 0 do
    if DateTime.compare(from, to) == :gt do
      {:error, "`from` datetime must be before `to` datetime"}
    else
      timestamps = generate_timestamps(from, to, interval_seconds)
      sleep_ms = Keyword.get(opts, :sleep_between_requests_ms, @default_sleep_ms)
      work_opts = Keyword.drop(opts, [:sleep_between_requests_ms])

      Logger.info(
        "[CMC Historical] Starting backfill from #{DateTime.to_iso8601(from)} " <>
          "to #{DateTime.to_iso8601(to)} with #{interval_seconds}s interval " <>
          "(#{length(timestamps)} requests)"
      )

      total = length(timestamps)

      {successes, failures} =
        timestamps
        |> Enum.with_index(1)
        |> Enum.reduce({0, 0}, fn {datetime, index}, {ok_count, err_count} ->
          Logger.info(
            "[CMC Historical] Request #{index}/#{total}: #{DateTime.to_iso8601(datetime)}"
          )

          result =
            try do
              TickerFetcher.work(Keyword.put(work_opts, :datetime, datetime))
            rescue
              e ->
                Logger.error(
                  "[CMC Historical] Exception for #{DateTime.to_iso8601(datetime)}: #{Exception.message(e)}"
                )

                {:error, :exception}
            end

          if total > 1, do: Process.sleep(sleep_ms)

          case result do
            :ok -> {ok_count + 1, err_count}
            {:error, _} -> {ok_count, err_count + 1}
          end
        end)

      Logger.info(
        "[CMC Historical] Backfill complete. " <>
          "Successful: #{successes}, Failed: #{failures}"
      )

      {:ok, successes}
    end
  end

  defp generate_timestamps(from, to, interval_seconds) do
    Stream.iterate(from, fn dt -> DateTime.add(dt, interval_seconds, :second) end)
    |> Enum.take_while(fn dt -> DateTime.compare(dt, to) != :gt end)
  end
end

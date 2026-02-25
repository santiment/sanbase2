defmodule Sanbase.Cryptocompare.Backfill do
  @moduledoc ~s"""
  Utility module for discovering and backfilling missing derivatives data
  (funding_rate, open_interest) in ClickHouse.

  Designed to be run manually from an IEx console:

      # Find missing days for one instrument
      {:ok, days} = Sanbase.Cryptocompare.Backfill.find_missing_days(
        "funding_rate", "hyperliquid", "BTC-USD", from: ~D[2024-01-01]
      )

      # Find all missing days for a market
      {:ok, all} = Sanbase.Cryptocompare.Backfill.find_all_missing_days(
        "funding_rate", "hyperliquid", from: ~D[2024-01-01]
      )

      # Dry run — see what jobs would be created
      {:ok, jobs} = Sanbase.Cryptocompare.Backfill.schedule_jobs(
        :funding_rate, "hyperliquid", all, dry_run: true
      )

      # Actually schedule the jobs
      {:ok, count} = Sanbase.Cryptocompare.Backfill.schedule_jobs(
        :funding_rate, "hyperliquid", all, dry_run: false
      )
  """

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Clickhouse.Query

  @oban_conf_name :oban_scrapers
  @allowed_tables ~w(funding_rate open_interest)

  @doc """
  Find missing days for a single market/instrument pair.

  Returns `{:ok, [Date.t()]}` — a sorted list of dates that have no data.

  Options:
    * `:from` — start date (default: first day with data in the table)
    * `:to` — end date (default: yesterday)
  """
  def find_missing_days(table, market, instrument, opts \\ [])
      when table in @allowed_tables do
    to = Keyword.get(opts, :to, Date.add(Date.utc_today(), -1))

    with {:ok, from} <- resolve_from_date(table, market, instrument, opts),
         {:ok, existing_days} <- query_existing_days(table, market, instrument, from, to) do
      expected = Date.range(from, to) |> MapSet.new()
      existing = MapSet.new(existing_days)
      missing = MapSet.difference(expected, existing) |> Enum.sort(Date)

      {:ok, missing}
    end
  end

  @doc """
  Find missing days for all instruments on a given market.

  Returns `{:ok, %{instrument => [Date.t()]}}`.

  Options:
    * `:from` — start date (default: first day with data per instrument)
    * `:to` — end date (default: yesterday)
  """
  def find_all_missing_days(table, market, opts \\ [])
      when table in @allowed_tables do
    to = Keyword.get(opts, :to, Date.add(Date.utc_today(), -1))

    with {:ok, rows} <- query_all_instrument_days(table, market, opts, to) do
      grouped =
        Enum.group_by(
          rows,
          fn {instrument, _day} -> instrument end,
          fn {_instrument, day} -> day end
        )

      result =
        Enum.map(grouped, fn {instrument, existing_days} ->
          from = Keyword.get(opts, :from) || Enum.min(existing_days, Date)
          expected = Date.range(from, to) |> MapSet.new()
          existing = MapSet.new(existing_days)
          missing = MapSet.difference(expected, existing) |> Enum.sort(Date)
          {instrument, missing}
        end)
        |> Enum.reject(fn {_instrument, missing} -> missing == [] end)
        |> Map.new()

      {:ok, result}
    end
  end

  @doc """
  Schedule Oban backfill jobs for missing days.

  Accepts either:
    * A list of dates (from `find_missing_days/4`) — you must also pass the instrument via `:instrument` opt
    * A map of `%{instrument => [dates]}` (from `find_all_missing_days/3`)

  Options:
    * `:limit` — data points per job (default: `default_limit(market)`)
    * `:version` — "v1" or "v2", only for open_interest (default: "v1")
    * `:dry_run` — when true, returns job changesets without inserting (default: true)
    * `:instrument` — required when passing a flat list of dates
  """
  def schedule_jobs(type, market, missing_days, opts \\ [])

  def schedule_jobs(type, market, missing_days, opts) when is_list(missing_days) do
    instrument = Keyword.fetch!(opts, :instrument)
    schedule_jobs(type, market, %{instrument => missing_days}, opts)
  end

  def schedule_jobs(type, market, missing_days_map, opts) when is_map(missing_days_map) do
    dry_run = Keyword.get(opts, :dry_run, true)
    limit = Keyword.get(opts, :limit, default_limit(market))
    version = Keyword.get(opts, :version, "v1")

    jobs =
      for {instrument, dates} <- missing_days_map,
          date <- dates do
        build_job(type, market, instrument, date, limit, version)
      end

    if dry_run do
      {:ok, jobs}
    else
      jobs
      |> Enum.chunk_every(200)
      |> Enum.each(&Oban.insert_all(@oban_conf_name, &1))

      {:ok, length(jobs)}
    end
  end

  @doc """
  Default number of data points to request per job.

  hyperliquid has ~24-48 data points/day (hourly),
  while other markets have ~1440/day (per-minute).
  """
  def default_limit("hyperliquid"), do: 48
  def default_limit(_market), do: 1440

  # --- Private ---

  defp build_job(:funding_rate, market, instrument, date, limit, _version) do
    timestamp = date |> Date.add(1) |> date_to_unix()

    Sanbase.Cryptocompare.FundingRate.HistoricalWorker.new(%{
      market: market,
      instrument: instrument,
      timestamp: timestamp,
      schedule_next_job: false,
      limit: limit
    })
  end

  defp build_job(:open_interest, market, instrument, date, limit, version) do
    timestamp = date |> Date.add(1) |> date_to_unix()

    Sanbase.Cryptocompare.OpenInterest.HistoricalWorker.new(%{
      market: market,
      instrument: instrument,
      timestamp: timestamp,
      schedule_next_job: false,
      limit: limit,
      version: version
    })
  end

  defp date_to_unix(date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC") |> DateTime.to_unix()
  end

  defp resolve_from_date(table, market, instrument, opts) do
    case Keyword.get(opts, :from) do
      %Date{} = from ->
        {:ok, from}

      nil ->
        query_first_day(table, market, instrument)
    end
  end

  defp query_first_day(table, market, instrument) do
    query =
      Query.new(
        """
        SELECT toDate(min(dt)) AS first_day
        FROM #{table}
        WHERE market = {{market}} AND instrument = {{instrument}}
        """,
        %{market: market, instrument: instrument}
      )

    case ClickhouseRepo.query_transform(query, fn [day] -> day end) do
      {:ok, [day]} -> {:ok, day}
      {:ok, _} -> {:error, :no_data}
      {:error, error} -> {:error, error}
    end
  end

  defp query_existing_days(table, market, instrument, from, to) do
    IO.inspect({from, to})

    query =
      Query.new(
        """
        SELECT DISTINCT toDate(dt) AS day
        FROM #{table}
        WHERE market = {{market}}
          AND instrument = {{instrument}}
          AND dt >= toDate({{from}})
          AND dt <= toDate({{to}})
        ORDER BY day
        """,
        %{
          market: market,
          instrument: instrument,
          from: Date.to_iso8601(from),
          to: Date.to_iso8601(to)
        }
      )

    ClickhouseRepo.query_transform(query, fn [day] -> day end)
  end

  defp query_all_instrument_days(table, market, opts, to) do
    from = Keyword.get(opts, :from)

    sql = """
    SELECT instrument, toDate(dt) AS day
    FROM #{table}
    WHERE market = {{market}}
      #{if from, do: "AND dt >= toDate({{from}})"}
      AND dt <= toDate({{to}})
    GROUP BY instrument, day
    ORDER BY instrument, day
    """

    params = %{market: market, from: Date.to_iso8601(from), to: Date.to_iso8601(to)}

    query = Query.new(sql, params)

    ClickhouseRepo.query_transform(query, fn [instrument, day] ->
      {instrument, Date.from_iso8601!(day)}
    end)
  end
end

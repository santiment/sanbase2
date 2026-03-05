defmodule Sanbase.Cryptocompare.Backfill do
  @moduledoc ~s"""
  Utility module for discovering and backfilling missing derivatives data
  (funding_rate, open_interest) in ClickHouse.

  Designed to be run manually from an IEx console:

      # Find missing days for one mapped_instrument
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
  Find missing days for a single market/mapped_instrument pair.

  Returns `{:ok, [Date.t()]}` — a sorted list of dates that have no data.

  Options:
    * `:from` — start date (default: first day with data in the table)
    * `:to` — end date (default: yesterday)
  """
  @spec find_missing_days(String.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, [Date.t()]} | {:error, term()}
  def find_missing_days(table, market, mapped_instrument, opts \\ [])
      when table in @allowed_tables do
    to = resolve_to_date(opts)

    with {:ok, from} <- resolve_from_date(table, market, mapped_instrument, opts),
         :ok <- validate_date_range(from, to),
         {:ok, existing_days} <- query_existing_days(table, market, mapped_instrument, from, to) do
      expected = Date.range(from, to) |> MapSet.new()
      existing = MapSet.new(existing_days)
      missing = MapSet.difference(expected, existing) |> Enum.sort(Date)

      {:ok, missing}
    end
  end

  @doc """
  Find missing days for all mapped_instruments on a given market.

  Returns `{:ok, %{mapped_instrument => [Date.t()]}}`.

  Options:
    * `:from` — start date (default: first day with data per mapped_instrument)
    * `:to` — end date (default: yesterday)
  """
  @spec find_all_missing_days(String.t(), String.t(), Keyword.t()) ::
          {:ok, %{String.t() => [Date.t()]}} | {:error, term()}
  def find_all_missing_days(table, market, opts \\ [])
      when table in @allowed_tables do
    to = resolve_to_date(opts)

    with {:ok, rows} <- query_all_mapped_instrument_days(table, market, opts, to) do
      grouped =
        Enum.group_by(
          rows,
          fn {mapped_instrument, _day} -> mapped_instrument end,
          fn {_mapped_instrument, day} -> day end
        )

      result =
        Enum.map(grouped, fn {mapped_instrument, existing_days} ->
          from = Keyword.get(opts, :from) || Enum.min(existing_days, Date)
          expected = Date.range(from, to) |> MapSet.new()
          existing = MapSet.new(existing_days)
          missing = MapSet.difference(expected, existing) |> Enum.sort(Date)
          {mapped_instrument, missing}
        end)
        |> Enum.reject(fn {_mapped_instrument, missing} -> missing == [] end)
        |> Map.new()

      {:ok, result}
    end
  end

  @doc """
  Schedule Oban backfill jobs for missing days.

  Accepts either:
    * A list of dates (from `find_missing_days/4`) — you must also pass the mapped_instrument via `:mapped_instrument` opt
    * A map of `%{mapped_instrument => [dates]}` (from `find_all_missing_days/3`)

  Options:
    * `:limit` — data points per job (default: `default_limit(market)`)
    * `:version` — "v1" or "v2", only for open_interest (default: "v1")
    * `:dry_run` — when true, returns job changesets without inserting (default: true)
    * `:mapped_instrument` — required when passing a flat list of dates
  """
  @spec schedule_jobs(atom(), String.t(), [Date.t()] | %{String.t() => [Date.t()]}, Keyword.t()) ::
          {:ok, [Oban.Job.changeset()]} | {:ok, non_neg_integer()} | {:error, term()}
  def schedule_jobs(type, market, missing_days, opts \\ [])

  def schedule_jobs(type, market, missing_days, opts) when is_list(missing_days) do
    case Keyword.fetch(opts, :mapped_instrument) do
      {:ok, mapped_instrument} ->
        schedule_jobs(type, market, %{mapped_instrument => missing_days}, opts)

      :error ->
        {:error, ":mapped_instrument option is required when passing a list of dates"}
    end
  end

  def schedule_jobs(type, market, missing_days_map, opts) when is_map(missing_days_map) do
    dry_run = Keyword.get(opts, :dry_run, true)
    limit = Keyword.get(opts, :limit, default_limit(market))
    version = Keyword.get(opts, :version, "v1")

    jobs =
      for {mapped_instrument, dates} <- missing_days_map,
          date <- dates do
        build_job(type, market, mapped_instrument, date, limit, version)
      end

    if dry_run do
      {:ok, jobs}
    else
      results =
        jobs
        |> Enum.chunk_every(200)
        |> Enum.flat_map(&Oban.insert_all(@oban_conf_name, &1))

      {:ok, length(results)}
    end
  end

  @doc """
  Default number of data points to request per job.

  hyperliquid has ~24-48 data points/day (hourly),
  while other markets have ~1440/day (per-minute).
  """
  @spec default_limit(String.t()) :: pos_integer()
  def default_limit("hyperliquid"), do: 48
  def default_limit(_market), do: 1440

  # --- Private ---

  defp build_job(:funding_rate, market, mapped_instrument, date, limit, _version) do
    timestamp = date |> Date.add(1) |> date_to_unix()

    Sanbase.Cryptocompare.FundingRate.HistoricalWorker.new(%{
      market: market,
      instrument: mapped_instrument,
      timestamp: timestamp,
      schedule_next_job: false,
      limit: limit
    })
  end

  defp build_job(:open_interest, market, mapped_instrument, date, limit, version) do
    timestamp = date |> Date.add(1) |> date_to_unix()

    Sanbase.Cryptocompare.OpenInterest.HistoricalWorker.new(%{
      market: market,
      instrument: mapped_instrument,
      timestamp: timestamp,
      schedule_next_job: false,
      limit: limit,
      version: version
    })
  end

  defp date_to_unix(date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC") |> DateTime.to_unix()
  end

  defp resolve_to_date(opts) do
    case Keyword.get(opts, :to) do
      %Date{} = to -> to
      nil -> Date.add(Date.utc_today(), -1)
    end
  end

  defp validate_date_range(from, to) do
    if Date.compare(from, to) in [:lt, :eq], do: :ok, else: {:error, :invalid_date_range}
  end

  defp resolve_from_date(table, market, mapped_instrument, opts) do
    case Keyword.get(opts, :from) do
      %Date{} = from ->
        {:ok, from}

      nil ->
        query_first_day(table, market, mapped_instrument)
    end
  end

  defp query_first_day(table, market, mapped_instrument) do
    query =
      Query.new(
        """
        SELECT toDate(min(dt)) AS first_day
        FROM #{table}
        WHERE market = {{market}} AND mapped_instrument = {{mapped_instrument}}
        HAVING count() > 0
        """,
        %{market: market, mapped_instrument: mapped_instrument}
      )

    case ClickhouseRepo.query_transform(query, fn [day] -> day end) do
      {:ok, [day]} -> {:ok, day}
      {:ok, _} -> {:error, :no_data}
      {:error, error} -> {:error, error}
    end
  end

  defp query_existing_days(table, market, mapped_instrument, from, to) do
    query =
      Query.new(
        """
        SELECT DISTINCT toDate(dt) AS day
        FROM #{table}
        WHERE market = {{market}}
          AND mapped_instrument = {{mapped_instrument}}
          AND toDate(dt) >= toDate({{from}})
          AND toDate(dt) <= toDate({{to}})
        ORDER BY day
        """,
        %{
          market: market,
          mapped_instrument: mapped_instrument,
          from: Date.to_iso8601(from),
          to: Date.to_iso8601(to)
        }
      )

    ClickhouseRepo.query_transform(query, fn [day] -> day end)
  end

  defp query_all_mapped_instrument_days(table, market, opts, to) do
    from = Keyword.get(opts, :from)

    sql = """
    SELECT mapped_instrument, toDate(dt) AS day
    FROM #{table}
    WHERE market = {{market}}
      #{if from, do: "AND toDate(dt) >= toDate({{from}})"}
      AND toDate(dt) <= toDate({{to}})
    GROUP BY mapped_instrument, day
    ORDER BY mapped_instrument, day
    """

    params = %{market: market, to: Date.to_iso8601(to)}
    params = if from, do: Map.put(params, :from, Date.to_iso8601(from)), else: params

    query = Query.new(sql, params)

    ClickhouseRepo.query_transform(query, fn [mapped_instrument, day] ->
      {mapped_instrument, day}
    end)
  end
end

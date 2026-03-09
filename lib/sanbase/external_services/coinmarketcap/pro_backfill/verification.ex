defmodule Sanbase.ExternalServices.Coinmarketcap.ProBackfill.Verification do
  alias Sanbase.Price
  alias Sanbase.Project

  @step_seconds 300
  @max_fillable_interval "5m"
  @default_discovery_days 7

  def gap_check(opts) do
    with {:ok, scope} <- fetch_scope(opts),
         {:ok, from, to} <- fetch_interval(opts, scope) do
      projects = projects_for_scope(scope, opts)

      per_asset =
        projects
        |> Enum.map(&gap_check_project(&1, from, to))

      missing_assets =
        per_asset
        |> Enum.filter(&(length(&1.fillable_missing_ranges) > 0))

      fillable_now_assets = Enum.count(per_asset, &(length(&1.fillable_missing_ranges) > 0))
      deferred_assets = Enum.count(per_asset, &(length(&1.deferred_missing_ranges) > 0))
      {recommended_from, recommended_to} = recommended_interval(per_asset)

      {:ok,
       %{
         scope: scope,
         interval: @max_fillable_interval,
         time_start: from,
         time_end: to,
         has_gap: missing_assets != [],
         total_assets: length(per_asset),
         fillable_now_assets: fillable_now_assets,
         deferred_assets: deferred_assets,
         recommended_time_start: recommended_from,
         recommended_time_end: recommended_to,
         assets: per_asset
       }}
    end
  end

  def gap_check_project(%Project{slug: slug} = project, %DateTime{} = from, %DateTime{} = to) do
    expected =
      expected_timestamps(from, to)
      |> MapSet.new()

    actual =
      case Price.timeseries_metric_data(slug, "price_usd", from, to, @max_fillable_interval,
             source: "coinmarketcap"
           ) do
        {:ok, points} ->
          points
          |> Enum.map(&DateTime.to_unix(&1.datetime))
          |> MapSet.new()

        _ ->
          MapSet.new()
      end

    missing = MapSet.difference(expected, actual) |> MapSet.to_list() |> Enum.sort()
    missing_ranges = timestamps_to_ranges(missing)
    {fillable_ranges, deferred_ranges} = split_fillable_ranges(missing_ranges)

    %{
      project_id: project.id,
      slug: slug,
      fillable_missing_ranges: fillable_ranges,
      deferred_missing_ranges: deferred_ranges,
      missing_points_count: length(missing),
      expected_points_count: MapSet.size(expected),
      actual_points_count: MapSet.size(actual)
    }
  end

  def expected_timestamps(%DateTime{} = from, %DateTime{} = to) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    Stream.unfold(from_unix, fn ts ->
      if ts <= to_unix do
        {ts, ts + @step_seconds}
      else
        nil
      end
    end)
    |> Enum.to_list()
  end

  def timestamps_to_ranges([]), do: []

  def timestamps_to_ranges([first | rest]) do
    {ranges, start_ts, end_ts} =
      Enum.reduce(rest, {[], first, first}, fn ts, {ranges, start_ts, end_ts} ->
        if ts == end_ts + @step_seconds do
          {ranges, start_ts, ts}
        else
          {[%{from_unix: start_ts, to_unix: end_ts} | ranges], ts, ts}
        end
      end)

    Enum.reverse([%{from_unix: start_ts, to_unix: end_ts} | ranges])
  end

  def split_fillable_ranges(ranges) do
    fillable_to_unix = fillable_to_unix()

    Enum.reduce(ranges, {[], []}, fn %{from_unix: from_unix, to_unix: to_unix},
                                     {fillable, deferred} ->
      cond do
        from_unix > fillable_to_unix ->
          {fillable, [%{from_unix: from_unix, to_unix: to_unix} | deferred]}

        to_unix <= fillable_to_unix ->
          {[%{from_unix: from_unix, to_unix: to_unix} | fillable], deferred}

        true ->
          split_fillable = %{from_unix: from_unix, to_unix: fillable_to_unix}
          split_deferred = %{from_unix: fillable_to_unix + @step_seconds, to_unix: to_unix}
          {[split_fillable | fillable], [split_deferred | deferred]}
      end
    end)
    |> then(fn {fillable, deferred} ->
      {
        Enum.reverse(fillable) |> Enum.filter(&range_valid?/1),
        Enum.reverse(deferred) |> Enum.filter(&range_valid?/1)
      }
    end)
  end

  defp fetch_scope(opts) do
    case Keyword.get(opts, :scope) do
      scope when scope in [:single, :all, :list] -> {:ok, scope}
      scope when scope in ["single", "all", "list"] -> {:ok, String.to_existing_atom(scope)}
      _ -> {:error, "Invalid scope. Expected :single, :all or :list"}
    end
  rescue
    ArgumentError -> {:error, "Invalid scope. Expected :single, :all or :list"}
  end

  defp fetch_interval(opts, scope) do
    from = Keyword.get(opts, :time_start)
    to = Keyword.get(opts, :time_end)

    case {from, to} do
      {%DateTime{} = from, %DateTime{} = to} ->
        {:ok, from, to}

      {nil, nil} when scope == :single ->
        discovery_to_unix = fillable_to_unix()
        discovery_from_unix = discovery_to_unix - @default_discovery_days * 86_400

        {:ok, DateTime.from_unix!(discovery_from_unix), DateTime.from_unix!(discovery_to_unix)}

      {nil, nil} ->
        {:error, "Both :time_start and :time_end are required for :all and :list scopes"}

      _ ->
        {:error, "Both :time_start and :time_end must be DateTime"}
    end
  end

  defp projects_for_scope(:all, _opts) do
    Project.List.projects_with_source("coinmarketcap", include_hidden: true, order_by_rank: true)
  end

  defp projects_for_scope(:single, opts) do
    case Keyword.get(opts, :slug) do
      slug when is_binary(slug) ->
        case Project.by_slug(slug) do
          %Project{} = project -> [project]
          nil -> []
        end

      _ ->
        []
    end
  end

  defp projects_for_scope(:list, opts) do
    slugs = Keyword.get(opts, :slugs, []) |> List.wrap()

    slugs
    |> Enum.map(&Project.by_slug/1)
    |> Enum.reject(&is_nil/1)
  end

  defp fillable_to_unix do
    Date.utc_today()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.to_unix()
    |> Kernel.-(@step_seconds)
  end

  defp recommended_interval(per_asset) do
    all_fillable_ranges =
      per_asset
      |> Enum.flat_map(& &1.fillable_missing_ranges)

    case all_fillable_ranges do
      [] ->
        {nil, nil}

      ranges ->
        from_unix = ranges |> Enum.map(& &1.from_unix) |> Enum.min()
        to_unix = ranges |> Enum.map(& &1.to_unix) |> Enum.max()
        {DateTime.from_unix!(from_unix), DateTime.from_unix!(to_unix)}
    end
  end

  defp range_valid?(%{from_unix: from_unix, to_unix: to_unix}), do: from_unix <= to_unix
end

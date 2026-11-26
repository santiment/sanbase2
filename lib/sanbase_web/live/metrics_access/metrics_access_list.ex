defmodule SanbaseWeb.MetricsAccessList do
  @moduledoc """
  The pure side of the metrics access page (`SanbaseWeb.MetricsAccessLive`): the
  URL state (parsing, rebuilding, defaults), and turning the cached rows into the
  list on screen - variants expanded or not, search, show locked, access filter,
  category, sort - plus the counts shown around it.

  The plan view shows one plan in both channels; its access filter matches a row
  when either channel matches. The compare view shows every plan in one channel,
  with no selected plan, access filter or show locked. Sorting follows the
  clicked column header: the metric name, an access column (by `rank/1`) or, by
  default, the taxonomy.
  """
  use SanbaseWeb, :verified_routes

  alias Sanbase.Billing.Plan.PlanMetricAccess

  @default_plan "free"
  @max_query_length 100

  @access_options [
    {:all, "all", "All metrics"},
    {:full, "full", "Full access"},
    {:no_delay, "no_delay", "No delay"},
    {:delayed, "delayed", "Delayed"},
    {:all_history, "all_history", "All history"},
    {:limited_history, "limited_history", "Limited history"}
  ]

  # Each URL param's default value, left out of URLs.
  @param_defaults %{
    plan: @default_plan,
    view: "plan",
    channel: "api",
    category: nil,
    q: "",
    dates: "relative",
    locked: "hide",
    access: "all",
    sort: nil,
    dir: "asc",
    variants: "collapsed"
  }

  # Seconds per unit of an interval suffix such as "_24h" or "_7d".
  @interval_units %{
    "s" => 1,
    "m" => 60,
    "h" => 3600,
    "d" => 86_400,
    "w" => 604_800,
    "y" => 31_536_000
  }

  @type filter :: %{
          plan: String.t(),
          view: :plan | :compare,
          channel: :sanbase | :api,
          category: String.t() | nil,
          q: String.t(),
          dates: :relative | :exact,
          locked: :hide | :show,
          access: atom(),
          sort: :category | :metric | :sanbase | :api | {:plan, String.t()},
          dir: :asc | :desc,
          variants: :collapsed | :expanded
        }

  @doc "`{value, param, label}` of the access filter options, default first."
  def access_options(), do: @access_options

  ## URL state

  @doc "The filter in `params`; anything unknown falls back to its default."
  @spec parse(map(), [PlanMetricAccess.row()]) :: filter()
  def parse(params, rows) do
    params
    |> parse_all(rows)
    |> view_defaults()
  end

  # The compare view has no selected plan, so no access filter and no show
  # locked either: those params are ignored there. The plan view shows both
  # channels, so it ignores `channel`. A sort by a column the view does not
  # have (a channel in compare, a plan in the plan view) falls back to the
  # default order, which has no direction (always ascending).
  defp view_defaults(%{view: :compare} = filter) do
    %{filter | plan: @default_plan, access: :all, locked: :hide}
    |> sortable_by(&(&1 in [:category, :metric] or match?({:plan, _}, &1)))
  end

  defp view_defaults(filter) do
    %{filter | channel: :api}
    |> sortable_by(&(&1 in [:category, :metric, :sanbase, :api]))
  end

  defp sortable_by(filter, sortable?) do
    if sortable?.(filter.sort) and filter.sort != :category,
      do: filter,
      else: %{filter | sort: :category, dir: :asc}
  end

  defp parse_all(params, rows) do
    %{
      plan: parse_plan(params["plan"]),
      view: if(params["view"] == "compare", do: :compare, else: :plan),
      channel: if(params["channel"] == "sanbase", do: :sanbase, else: :api),
      category: parse_category(params["category"], rows),
      q: normalize_query(params["q"]),
      dates: parse_dates(params["dates"]),
      locked: if(params["locked"] == "show", do: :show, else: :hide),
      access: parse_option(params["access"], @access_options),
      sort: parse_sort(params["sort"]),
      dir: if(params["dir"] == "desc", do: :desc, else: :asc),
      variants: parse_variants(params["variants"])
    }
  end

  def parse_dates("exact"), do: :exact
  def parse_dates(_), do: :relative

  def parse_variants("expanded"), do: :expanded
  def parse_variants(_), do: :collapsed

  def parse_option(param, options) do
    case List.keyfind(options, param, 1) do
      {value, _param, _label} -> value
      nil -> options |> hd() |> elem(0)
    end
  end

  def normalize_query(q) when is_binary(q),
    do: q |> String.trim() |> String.slice(0, @max_query_length)

  def normalize_query(_), do: ""

  defp parse_sort("metric"), do: :metric
  defp parse_sort("sanbase"), do: :sanbase
  defp parse_sort("api"), do: :api

  defp parse_sort(param) do
    if Enum.any?(PlanMetricAccess.plans(), &(&1.key == param)),
      do: {:plan, param},
      else: :category
  end

  defp sort_param(:category), do: nil
  defp sort_param({:plan, key}), do: key
  defp sort_param(sort), do: Atom.to_string(sort)

  defp parse_plan(plan) do
    if Enum.any?(PlanMetricAccess.plans(), &(&1.key == plan)), do: plan, else: @default_plan
  end

  defp parse_category(slug, rows) when is_binary(slug) do
    if Enum.any?(rows, &(&1.category_slug == slug)), do: slug
  end

  defp parse_category(_slug, _rows), do: nil

  @doc """
  The URL of `filter`. Defaults are left out, so the bare URL is the default
  view. The channel only counts in the compare view; the plan, the access filter
  and show locked only in the plan view.
  """
  @spec path(filter()) :: String.t()
  def path(filter) do
    filter = view_defaults(filter)

    query =
      [
        plan: filter.plan,
        view: Atom.to_string(filter.view),
        channel: Atom.to_string(filter.channel),
        category: filter.category,
        q: filter.q,
        dates: Atom.to_string(filter.dates),
        locked: Atom.to_string(filter.locked),
        access: @access_options |> List.keyfind(filter.access, 0) |> elem(1),
        sort: sort_param(filter.sort),
        # The default order has no direction.
        dir: if(filter.sort == :category, do: "asc", else: Atom.to_string(filter.dir)),
        variants: Atom.to_string(filter.variants)
      ]
      |> Enum.reject(fn {key, value} -> value == Map.fetch!(@param_defaults, key) end)

    if query == [], do: ~p"/metrics_access", else: ~p"/metrics_access?#{query}"
  end

  @doc """
  The filter a click on a column header gives: sorted by `sort`, ascending (best
  access first, or A to Z) unless it already is, then descending. `:category`
  is the default order.
  """
  @spec sorted_by(filter(), atom() | {:plan, String.t()}) :: filter()
  def sorted_by(filter, :category), do: %{filter | sort: :category, dir: :asc}

  def sorted_by(filter, sort) do
    dir = if filter.sort == sort and filter.dir == :asc, do: :desc, else: :asc
    %{filter | sort: sort, dir: dir}
  end

  @doc """
  Every filter back to its default. What is not a filter stays: the plan, the
  view, the compare channel, the dates and the variants mode.
  """
  @spec cleared(filter()) :: filter()
  def cleared(filter) do
    %{filter | category: nil, q: "", locked: :hide, access: :all, sort: :category, dir: :asc}
  end

  @doc """
  Whether going from `old` to `new` changes the list itself (not only how its
  cells read), so the page starts again from its first page.
  """
  @spec new_list?(filter() | nil, filter()) :: boolean()
  def new_list?(nil, _new), do: true

  def new_list?(old, new) do
    Map.drop(old, [:plan, :dates]) != Map.drop(new, [:plan, :dates])
  end

  ## The list

  @doc """
  Everything the page shows about the list for `filter`:

    * `:entries` - the `{row, matched names}` on screen, in order
    * `:all_total` - every row (or variant, when expanded), no filter applied
    * `:included_rows` - the rows matching the search and the category, which the
      Included counts are taken over: show locked and the access filter would
      only hide the locked rows those counts are about
    * `:category_counts` - per category, the rows every other filter keeps
    * `:locked_hidden` - how many rows show locked hides (search and category
      applied)
  """
  @spec build([PlanMetricAccess.row()], filter()) :: map()
  def build(rows, filter) do
    rows = if filter.variants == :expanded, do: expand(rows), else: rows
    searched = search(rows, filter.q)
    in_category = in_category(searched, filter.category)
    shown = reject_locked(in_category, filter)

    other_filters = searched |> reject_locked(filter) |> filter_access(filter)

    %{
      entries: shown |> filter_access(filter) |> sort(filter),
      all_total: length(rows),
      included_rows: Enum.map(in_category, &elem(&1, 0)),
      category_counts: Enum.frequencies_by(other_filters, fn {row, _} -> row.category end),
      locked_hidden: length(in_category) - length(shown)
    }
  end

  @doc "The entries on screen for `filter`, as `build/2` lists them."
  def entries(rows, filter), do: build(rows, filter).entries

  @doc """
  One row per name: each variant of a row on its own, in the row's place, with
  its own names and the row's access and taxonomy.
  """
  @spec expand([PlanMetricAccess.row()]) :: [PlanMetricAccess.row()]
  def expand(rows) do
    Enum.flat_map(rows, fn row ->
      row.metrics
      |> sort_variants()
      |> Enum.map(fn metric ->
        name = Map.get(row.variant_names, metric, metric)

        %{
          row
          | id: "#{row.id}--#{metric}",
            name: name,
            metrics: [metric],
            variant_names: %{metric => name},
            search_text: String.downcase(name <> "\n" <> metric)
        }
      end)
    end)
  end

  @doc """
  Names in their natural order: those ending in an interval ("_1h", "_24h",
  "_7d") by its length, then the rest by name.
  """
  @spec sort_variants([String.t()]) :: [String.t()]
  def sort_variants(metrics), do: Enum.sort_by(metrics, &variant_sort_key/1)

  defp variant_sort_key(metric) do
    case Regex.run(~r/_(\d+)([smhdwy])$/, metric) do
      [_, amount, unit] ->
        {0, String.to_integer(amount) * Map.fetch!(@interval_units, unit), metric}

      nil ->
        {1, 0, metric}
    end
  end

  # `{row, matched names}` for the rows matching `q`, as a literal,
  # case-insensitive substring of a display or technical name.
  defp search(rows, ""), do: Enum.map(rows, &{&1, []})

  defp search(rows, q) do
    needle = String.downcase(q)

    Enum.flat_map(rows, fn row ->
      # `search_text` holds every name of the row, downcased, so one scan rules most
      # rows out; the names are only looked at one by one for the rows it keeps.
      if String.contains?(row.search_text, needle), do: matching(row, needle), else: []
    end)
  end

  defp matching(row, needle) do
    matched =
      Enum.filter(row.metrics, fn metric ->
        contains?(metric, needle) or contains?(Map.get(row.variant_names, metric), needle)
      end)

    # Both checks, not just `matched`: a needle spanning two of the joined names
    # matches `search_text` but no name.
    if matched != [] or contains?(row.name, needle),
      do: [{row, matched}],
      else: []
  end

  defp contains?(nil, _needle), do: false
  defp contains?(text, needle), do: String.contains?(String.downcase(text), needle)

  defp in_category(entries, nil), do: entries

  defp in_category(entries, slug),
    do: Enum.filter(entries, fn {row, _matched} -> row.category_slug == slug end)

  # The plan view hides the rows the plan has locked in both channels, unless
  # asked not to; the compare view shows every row.
  defp reject_locked(entries, %{view: :plan, locked: :hide, plan: plan}) do
    Enum.reject(entries, fn {row, _} ->
      locked?(row.access[{plan, :sanbase}]) and locked?(row.access[{plan, :api}])
    end)
  end

  defp reject_locked(entries, _filter), do: entries

  defp filter_access(entries, %{access: :all}), do: entries

  # Either channel. (The compare view has no access filter.)
  defp filter_access(entries, %{access: access, plan: plan}) do
    Enum.filter(entries, fn {row, _} ->
      access_matches?(row.access[{plan, :sanbase}], access) or
        access_matches?(row.access[{plan, :api}], access)
    end)
  end

  defp sort(entries, %{sort: :category}), do: entries

  # Enum.sort_by/3 is stable: ties keep the taxonomy order. Descending negates
  # the rank instead of reversing, for the same reason.
  defp sort(entries, %{sort: :metric, dir: dir}),
    do: Enum.sort_by(entries, fn {row, _} -> row.metrics |> sort_variants() |> hd() end, dir)

  defp sort(entries, %{dir: dir} = filter) do
    sign = if dir == :asc, do: 1, else: -1
    Enum.sort_by(entries, fn {row, _} -> sign * rank(sort_cell(row, filter)) end)
  end

  # The access an access-column sort reads.
  defp sort_cell(row, %{sort: {:plan, plan}, channel: channel}), do: row.access[{plan, channel}]
  defp sort_cell(row, %{sort: channel, plan: plan}), do: row.access[{plan, channel}]

  @doc "Whether an access value matches an access filter option. Locked never does."
  @spec access_matches?(PlanMetricAccess.access(), atom()) :: boolean()
  def access_matches?(_access, :all), do: true
  def access_matches?({:locked, _}, _option), do: false
  def access_matches?({:window, nil, nil}, :full), do: true
  def access_matches?({:window, _, nil}, :no_delay), do: true
  def access_matches?({:window, _, delay}, :delayed) when not is_nil(delay), do: true
  def access_matches?({:window, nil, _}, :all_history), do: true
  def access_matches?({:window, history, _}, :limited_history) when not is_nil(history), do: true
  def access_matches?(_access, _option), do: false

  @doc """
  0 is the most access: all history with no delay, then a limited history with no
  delay, all history with a delay, both limited, and locked last.
  """
  @spec rank(PlanMetricAccess.access()) :: 0..4
  def rank({:window, nil, nil}), do: 0
  def rank({:window, _history, nil}), do: 1
  def rank({:window, nil, _delay}), do: 2
  def rank({:window, _history, _delay}), do: 3
  def rank({:locked, _}), do: 4

  def locked?({:locked, _}), do: true
  def locked?(_), do: false
end

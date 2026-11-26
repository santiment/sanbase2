defmodule SanbaseWeb.MetricsAccessLive do
  @moduledoc """
  Public page: for a chosen plan, which metrics it includes and how much of their
  data, in Sanbase and through the API.

  The rows are never kept in the socket - every visitor would hold a copy. They
  are read from `PlanMetricAccess.rows/0` (cached) whenever the list is built, and
  streamed a page at a time.
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.MetricsAccessComponents

  alias Sanbase.Billing.Plan.PlanMetricAccess

  @page_size 150
  @default_plan "free"
  @max_query_length 100

  @impl true
  def mount(_params, _session, socket) do
    plans =
      Enum.map(PlanMetricAccess.plans(), fn plan ->
        headlines =
          Map.new(PlanMetricAccess.channels(), fn %{key: channel} ->
            {channel, PlanMetricAccess.headline(plan.key, channel)}
          end)

        Map.put(plan, :headlines, headlines)
      end)

    {:ok,
     socket
     |> assign(
       page_title: "Santiment | Metrics by plan",
       plans: plans,
       channels: PlanMetricAccess.channels(),
       filter: nil,
       loaded: @page_size
     )
     |> stream_configure(:rows, dom_id: & &1.id)
     |> stream(:rows, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    today = Date.utc_today()
    rows = PlanMetricAccess.rows()
    filter = parse_params(params, rows)

    # A new category or search starts from the first page; a plan or date change
    # redraws what is already on screen.
    loaded =
      case socket.assigns.filter do
        %{category: category, q: q} when category == filter.category and q == filter.q ->
          socket.assigns.loaded

        _ ->
          @page_size
      end

    searched = search(rows, filter.q)
    visible = in_category(searched, filter.category)
    page = Enum.take(visible, loaded)

    {:noreply,
     socket
     |> assign(filter: filter, today: today, total: length(visible))
     |> assign(loaded: max(length(page), @page_size), shown: length(page))
     |> assign_summary(rows, searched)
     |> stream(:rows, Enum.map(page, &row_item(&1, filter.plan)), reset: true)}
  end

  defp assign_summary(socket, rows, searched) do
    %{filter: filter, plans: plans} = socket.assigns

    assign(socket,
      counts: channel_counts(rows, filter.plan),
      categories: category_options(rows, searched),
      all_count: length(searched),
      plan: Enum.find(plans, &(&1.key == filter.plan)),
      search_form: to_form(%{"q" => filter.q, "category" => filter.category || "all"})
    )
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    %{filter: filter, shown: shown} = socket.assigns

    next =
      PlanMetricAccess.rows()
      |> search(filter.q)
      |> in_category(filter.category)
      |> Enum.drop(shown)
      |> Enum.take(@page_size)

    if next == [] do
      {:noreply, socket}
    else
      shown = shown + length(next)

      {:noreply,
       socket
       |> assign(shown: shown, loaded: max(shown, @page_size))
       |> stream(:rows, Enum.map(next, &row_item(&1, filter.plan)), at: -1)}
    end
  end

  # The form and the date toggle patch the URL; `handle_params/3` does the work, so
  # the address bar always describes the page. `replace: true` keeps a debounced
  # search box from adding a history entry per keystroke.
  def handle_event("filter", params, socket) do
    filter = socket.assigns.filter

    category =
      case params["category"] do
        nil -> filter.category
        "all" -> nil
        slug -> slug
      end

    filter = %{filter | q: normalize_query(params["q"] || filter.q), category: category}

    {:noreply, push_patch(socket, to: path(filter), replace: true)}
  end

  def handle_event("dates", %{"dates" => dates}, socket) do
    filter = %{socket.assigns.filter | dates: parse_dates(dates)}

    {:noreply, push_patch(socket, to: path(filter), replace: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="metrics-access" class="mx-auto w-full max-w-7xl -mt-10">
      <h1 class="text-2xl font-semibold tracking-tight">Santiment metrics by plan</h1>
      <p class="mt-1 text-sm text-base-content/70">
        Which metrics each plan includes, and how much of their data, in Sanbase and through the API.
      </p>

      <div class="my-4 rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
        <div class="flex flex-wrap items-end gap-4">
          <.plan_picker
            plans={@plans}
            selected={@filter.plan}
            path_fun={&path(%{@filter | plan: &1})}
          />

          <.form
            for={@search_form}
            id="metrics-access-filters"
            phx-change="filter"
            phx-submit="filter"
            class="flex min-w-0 grow basis-full flex-wrap items-end gap-4 md:basis-0"
          >
            <div class="w-full min-w-0 sm:w-auto sm:min-w-[16rem] sm:flex-1">
              <label for="metric-search" class="mb-1 block text-sm font-semibold">Search</label>
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass-mini"
                  class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-base-content/50"
                />
                <input
                  id="metric-search"
                  type="search"
                  name={@search_form[:q].name}
                  value={@search_form[:q].value}
                  maxlength="100"
                  placeholder="Metric name, e.g. mvrv"
                  autocomplete="off"
                  phx-debounce="200"
                  class="w-full rounded-lg border border-base-300 bg-base-100 py-2.5 pl-9 pr-3 text-sm outline-none transition-colors duration-150 placeholder:text-base-content/50 focus:border-primary focus:ring-2 focus:ring-primary/20"
                />
              </div>
            </div>
            <div class="min-w-0 grow basis-40 sm:w-56 sm:grow-0 sm:basis-auto">
              <label for="category-select" class="mb-1 block text-sm font-semibold">
                Category
              </label>
              <select
                id="category-select"
                name={@search_form[:category].name}
                class="w-full rounded-lg border border-base-300 bg-base-100 px-3 py-2.5 text-sm outline-none transition-colors duration-150 focus:border-primary focus:ring-2 focus:ring-primary/20"
              >
                <option id="category-all" value="all" selected={is_nil(@filter.category)}>
                  All categories ({delimit(@all_count)})
                </option>
                <option
                  :for={category <- @categories}
                  id={"category-#{category.slug}"}
                  value={category.slug}
                  selected={@filter.category == category.slug}
                >
                  {category.name} ({delimit(category.count)})
                </option>
              </select>
            </div>
          </.form>

          <.date_toggle dates={@filter.dates} />
        </div>
      </div>

      <.plan_summary
        plan={@plan}
        channels={@channels}
        counts={@counts}
        dates={@filter.dates}
        today={@today}
      />

      <p id="metric-count" class="mb-2 mt-6 text-sm text-base-content/70">
        Showing {delimit(@shown)} of {delimit(@total)} {if @total == 1,
          do: "metric",
          else: "metrics"} · access on {@plan.label}
      </p>

      <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100">
        <div class="overflow-x-auto">
          <table class="w-full min-w-[48rem] text-left">
            <thead class="border-b border-base-300 bg-base-200/50 text-xs text-base-content/70">
              <tr>
                <th scope="col" class="px-4 py-2.5 font-medium">Metric</th>
                <th scope="col" class="px-4 py-2.5 font-medium">Category</th>
                <th scope="col" class="px-4 py-2.5 font-medium">Group</th>
                <th :for={channel <- @channels} scope="col" class="px-4 py-2.5 font-medium">
                  {channel.label}
                </th>
              </tr>
            </thead>
            <tbody id="metric-rows" phx-update="stream">
              <.metric_row
                :for={{_dom_id, item} <- @streams.rows}
                item={item}
                channels={@channels}
                dates={@filter.dates}
                today={@today}
              />
            </tbody>
          </table>
        </div>

        <div :if={@total == 0} id="metric-empty" class="px-6 py-12 text-center">
          <p :if={@filter.q == ""} class="text-sm text-base-content/70">
            No metrics to show.
          </p>
          <p :if={@filter.q != ""} class="text-sm text-base-content/70">
            No metric matches “{@filter.q}”. Search looks at technical and display names.
          </p>
          <.link
            :if={@filter.q != ""}
            id="clear-search"
            patch={path(%{@filter | q: ""})}
            class="mt-3 inline-block text-sm font-medium text-primary hover:underline"
          >
            Clear search
          </.link>
        </div>

        <%!-- The hook loads the next page as this bar nears the window's bottom edge
             (Show more stays as the fallback). phx-viewport-bottom cannot do it: it
             binds to the table's overflow-x-auto wrapper, which never scrolls
             vertically. --%>
        <div
          :if={@shown < @total}
          id="load-more"
          phx-hook="LoadMoreOnVisible"
          class="flex justify-center border-t border-base-300 py-3"
        >
          <button
            id="show-more"
            type="button"
            phx-click="load_more"
            class="rounded-lg border border-base-300 px-4 py-1.5 text-sm font-medium outline-none transition-colors duration-150 hover:bg-base-200 focus-visible:ring-2 focus-visible:ring-primary phx-click-loading:opacity-60"
          >
            Show more
            <span class="tabular-nums text-base-content/70">
              ({delimit(@total - @shown)} left)
            </span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  ## Params

  defp parse_params(params, rows) do
    %{
      plan: parse_plan(params["plan"]),
      category: parse_category(params["category"], rows),
      q: normalize_query(params["q"]),
      dates: parse_dates(params["dates"])
    }
  end

  defp parse_plan(plan) do
    if Enum.any?(PlanMetricAccess.plans(), &(&1.key == plan)), do: plan, else: @default_plan
  end

  defp parse_category(slug, rows) when is_binary(slug) do
    if Enum.any?(rows, &(&1.category_slug == slug)), do: slug
  end

  defp parse_category(_slug, _rows), do: nil

  defp parse_dates("exact"), do: :exact
  defp parse_dates(_), do: :relative

  defp normalize_query(q) when is_binary(q),
    do: q |> String.trim() |> String.slice(0, @max_query_length)

  defp normalize_query(_), do: ""

  # Defaults are left out, so the bare URL is the default view.
  defp path(filter) do
    query =
      [
        plan: if(filter.plan != @default_plan, do: filter.plan),
        category: filter.category,
        q: if(filter.q != "", do: filter.q),
        dates: if(filter.dates == :exact, do: "exact")
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    if query == [], do: ~p"/metrics_access", else: ~p"/metrics_access?#{query}"
  end

  ## Rows

  # `{row, matched names}` for the rows matching `q`, as a literal,
  # case-insensitive substring of the display name or any technical name.
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
    matched = Enum.filter(row.metrics, &String.contains?(String.downcase(&1), needle))

    # Both checks, not just `matched`: a needle spanning two of the joined names
    # matches `search_text` but no name.
    if matched != [] or String.contains?(String.downcase(row.name), needle),
      do: [{row, matched}],
      else: []
  end

  defp in_category(entries, nil), do: entries

  defp in_category(entries, slug),
    do: Enum.filter(entries, fn {row, _matched} -> row.category_slug == slug end)

  defp row_item({row, matched}, plan) do
    access = %{sanbase: row.access[{plan, :sanbase}], api: row.access[{plan, :api}]}
    [primary | variants] = row.metrics

    %{
      id: "metric-#{row.id}",
      name: row.name,
      primary: primary,
      variants: variants,
      category: row.category,
      group: row.group,
      # Listed inline only when the search picks out some of the names; when every
      # name matches, the row as a whole is the match.
      matched: if(length(matched) < length(row.metrics), do: matched, else: []),
      access: access,
      locked?: Enum.all?(Map.values(access), &match?({:locked, _}, &1))
    }
  end

  ## Summary and category options

  # Per channel: how many rows the plan includes, and for the rest, which plan
  # unlocks them - the lowest listed plan, or none (custom plan only).
  defp channel_counts(rows, plan) do
    total = length(rows)

    Enum.map(PlanMetricAccess.channels(), fn %{key: channel, label: label} ->
      locked = locked_by_unlocking_plan(rows, plan, channel)

      %{
        key: channel,
        label: label,
        included: total - Enum.sum(Map.values(locked)),
        total: total,
        missing: missing(locked)
      }
    end)
  end

  # Unlocking plan key (nil: no listed plan) => number of rows locked.
  defp locked_by_unlocking_plan(rows, plan, channel) do
    rows
    |> Enum.flat_map(&unlocking_plan(&1.access[{plan, channel}]))
    |> Enum.frequencies()
  end

  defp unlocking_plan({:locked, plan_key}), do: [plan_key]
  defp unlocking_plan(_access), do: []

  defp missing(locked) do
    by_plan =
      for %{key: key, label: label} <- PlanMetricAccess.plans(),
          count = Map.get(locked, key),
          do: %{id: key, count: count, text: if(count == 1, do: "needs ", else: "need ") <> label}

    custom =
      case Map.get(locked, nil) do
        nil -> []
        count -> [%{id: "custom", count: count, text: "custom plan only"}]
      end

    by_plan ++ custom
  end

  # Every category on the page, in taxonomy order, counting the rows that match
  # the search. A category the search empties stays listed with 0.
  defp category_options(rows, searched) do
    counts = Enum.frequencies_by(searched, fn {row, _} -> row.category end)

    rows
    |> Enum.uniq_by(& &1.category)
    |> Enum.map(
      &%{slug: &1.category_slug, name: &1.category, count: Map.get(counts, &1.category, 0)}
    )
  end
end

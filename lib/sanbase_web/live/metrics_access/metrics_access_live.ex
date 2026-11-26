defmodule SanbaseWeb.MetricsAccessLive do
  @moduledoc """
  Public page: which metrics each plan includes, and how much of their data, in
  Sanbase and through the API. Two views: one plan across both channels, or every
  plan side by side in one channel.

  The rows are never kept in the socket - every visitor would hold a copy. They
  are read from `PlanMetricAccess.rows/0` (cached) whenever the list is built, and
  streamed a page at a time. All state lives in the URL
  (`SanbaseWeb.MetricsAccessList`).
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.MetricsAccessComponents

  alias Sanbase.Billing.Plan.PlanMetricAccess
  alias SanbaseWeb.MetricsAccessFormat
  alias SanbaseWeb.MetricsAccessList

  @page_size 150

  @impl true
  def mount(_params, _session, socket) do
    call_limits = Sanbase.ApiCallLimit.Restrictions.call_limits_per_month()

    note =
      MetricsAccessFormat.access_note(%{
        pro_api: PlanMetricAccess.headline("sanbase_pro", :api),
        pro_calls: Map.fetch!(call_limits, "sanbase_pro"),
        business_calls: Map.fetch!(call_limits, "sanapi_business_pro")
      })

    {:ok,
     socket
     |> assign(
       page_title: "Santiment | Metrics by plan",
       plans: PlanMetricAccess.plans(),
       channels: PlanMetricAccess.channels(),
       access_note: note,
       filter: nil,
       loaded: @page_size
     )
     |> stream_configure(:rows, dom_id: & &1.id)
     |> stream(:rows, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    rows = PlanMetricAccess.rows()
    filter = MetricsAccessList.parse(params, rows)
    list = MetricsAccessList.build(rows, filter)

    # A new list starts from the first page; a plan or date change redraws what
    # is already on screen.
    loaded =
      if MetricsAccessList.new_list?(socket.assigns.filter, filter),
        do: @page_size,
        else: socket.assigns.loaded

    page = Enum.take(list.entries, loaded)
    hues = category_hues(rows)

    {:noreply,
     socket
     |> assign(filter: filter, today: Date.utc_today(), hues: hues)
     # The variants explainer's example chips take the On-chain category's hue.
     |> assign(example_hue: Map.get(hues, "On-chain", "teal"))
     |> assign(total: length(list.entries), all_total: list.all_total)
     |> assign(loaded: max(length(page), @page_size), shown: length(page))
     |> assign_summary(rows, list)
     |> stream(:rows, Enum.map(page, &item(&1, filter, hues)), reset: true)}
  end

  defp assign_summary(socket, rows, list) do
    %{filter: filter, plans: plans} = socket.assigns
    unit = unit_fun(filter.variants)
    categories = category_options(rows, list.category_counts)

    assign(socket,
      unit: unit,
      plan: Enum.find(plans, &(&1.key == filter.plan)),
      counts: channel_counts(list.included_rows, filter.plan),
      plan_counts: plan_counts(list.included_rows, filter.channel),
      categories: categories,
      all_count: Enum.sum_by(categories, & &1.count),
      locked_hidden: list.locked_hidden,
      clearable?: filter.q != "" or not is_nil(filter.category) or filter.access != :all,
      chips: chips(filter, categories, list.locked_hidden),
      search_form: search_form(filter)
    )
  end

  defp search_form(filter) do
    to_form(%{
      "q" => filter.q,
      "category" => filter.category || "all",
      "access" => option_param(filter.access, MetricsAccessList.access_options())
    })
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    %{filter: filter, shown: shown, hues: hues} = socket.assigns

    next =
      PlanMetricAccess.rows()
      |> MetricsAccessList.entries(filter)
      |> Enum.drop(shown)
      |> Enum.take(@page_size)

    if next == [] do
      # The cached rows shrank under the page (a refresh): nothing is left to
      # load, so the Show more bar goes away instead of the hook asking forever.
      {:noreply, assign(socket, total: shown)}
    else
      shown = shown + length(next)

      {:noreply,
       socket
       |> assign(shown: shown, loaded: max(shown, @page_size))
       |> stream(:rows, Enum.map(next, &item(&1, filter, hues)), at: -1)}
    end
  end

  # The controls patch the URL; `handle_params/3` does the work, so the address
  # bar always describes the page. `replace: true` keeps a debounced search box
  # from adding a history entry per keystroke.
  def handle_event("filter", params, socket) do
    filter = socket.assigns.filter

    category =
      case params["category"] do
        nil -> filter.category
        "all" -> nil
        slug -> slug
      end

    filter = %{
      filter
      | q: MetricsAccessList.normalize_query(params["q"] || filter.q),
        category: category,
        access: option(params["access"], filter.access, MetricsAccessList.access_options())
    }

    patch(socket, filter)
  end

  # The segmented buttons send their option under "option" (see
  # `segmented_buttons/1`); a browser also sends the button's "value".
  def handle_event("dates", %{"option" => option}, socket),
    do: patch(socket, %{socket.assigns.filter | dates: MetricsAccessList.parse_dates(option)})

  def handle_event("variants", %{"option" => option}, socket) do
    patch(socket, %{socket.assigns.filter | variants: MetricsAccessList.parse_variants(option)})
  end

  # A malformed payload (not one the page's buttons send) changes nothing.
  def handle_event(event, _params, socket) when event in ["dates", "variants"],
    do: {:noreply, socket}

  def handle_event("toggle_locked", _params, socket) do
    filter = socket.assigns.filter
    patch(socket, %{filter | locked: if(filter.locked == :show, do: :hide, else: :show)})
  end

  defp patch(socket, filter),
    do: {:noreply, push_patch(socket, to: path(filter), replace: true)}

  defp option(nil, current, _options), do: current
  defp option(param, _current, options), do: MetricsAccessList.parse_option(param, options)

  defp option_param(value, options), do: options |> List.keyfind(value, 0) |> elem(1)

  defp path(filter), do: MetricsAccessList.path(filter)

  @impl true
  def render(assigns) do
    ~H"""
    <div id="metrics-access" class="mx-auto w-full max-w-7xl -mt-10">
      <header>
        <h1 class="text-2xl font-semibold tracking-tight">Santiment metrics by plan</h1>
        <p class="mt-1 text-sm text-base-content/70">
          Which metrics each plan includes, and how much of their data, in Sanbase and through the API.
        </p>
      </header>

      <%!-- A direct child of the page, so it stays stuck for the whole page. --%>
      <.plan_bar
        plans={@plans}
        view={@filter.view}
        selected={@filter.plan}
        channel={@filter.channel}
        plan_path={&path(%{@filter | view: :plan, plan: &1})}
        compare_path={path(%{@filter | view: :compare})}
        channel_path={&path(%{@filter | channel: &1})}
      />

      <section
        id="metrics-access-toolbar"
        aria-label="Filters"
        class="mt-2 rounded-xl border border-base-300 bg-base-200/40"
      >
        <div class="space-y-2 px-4 py-3">
          <.form
            for={@search_form}
            id="metrics-access-filters"
            phx-change="filter"
            phx-submit="filter"
            class="grid grid-cols-2 gap-2 lg:flex lg:flex-wrap lg:items-center"
          >
            <div class="relative col-span-2 lg:min-w-[16rem] lg:flex-1">
              <label for="metric-search" class="sr-only">Search metrics</label>
              <.icon
                name="hero-magnifying-glass-mini"
                class={
                  "pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 " <>
                    if(@filter.q != "", do: "text-primary", else: "text-base-content/50")
                }
              />
              <input
                id="metric-search"
                type="search"
                name={@search_form[:q].name}
                value={@search_form[:q].value}
                data-active={@filter.q != "" && "true"}
                maxlength="100"
                placeholder="Search metrics, e.g. mvrv"
                autocomplete="off"
                phx-debounce="200"
                class={[
                  "h-9 w-full rounded-lg border bg-base-100 pl-9 pr-9 text-sm outline-none transition-colors duration-150",
                  "placeholder:text-base-content/50 focus:border-primary focus:ring-2 focus:ring-primary/20",
                  "[&::-webkit-search-cancel-button]:hidden",
                  if(@filter.q != "",
                    do: "border-primary ring-2 ring-primary/20",
                    else: "border-base-300 hover:border-base-content/30"
                  )
                ]}
              />
              <.link
                :if={@filter.q != ""}
                id="search-clear"
                patch={path(%{@filter | q: ""})}
                aria-label="Clear search"
                class="absolute right-1.5 top-1/2 inline-flex size-6 -translate-y-1/2 cursor-pointer items-center justify-center rounded-md text-base-content/60 outline-none transition-colors duration-150 hover:bg-base-200 hover:text-base-content focus-visible:ring-2 focus-visible:ring-primary"
              >
                <.icon name="hero-x-mark-mini" class="size-4" />
              </.link>
            </div>

            <.prefixed_select
              id="category-select"
              name={@search_form[:category].name}
              prefix="Category"
              pad="pl-[4.75rem]"
              class={[
                "col-span-2 lg:w-80 lg:flex-none",
                @filter.view == :plan && "sm:col-span-1"
              ]}
            >
              <option id="category-all" value="all" selected={is_nil(@filter.category)}>
                All ({delimit(@all_count)} {@unit.(@all_count)})
              </option>
              <option
                :for={category <- @categories}
                id={"category-#{category.slug}"}
                value={category.slug}
                selected={@filter.category == category.slug}
              >
                {category.name} ({delimit(category.count)} {@unit.(category.count)})
              </option>
            </.prefixed_select>

            <.prefixed_select
              :if={@filter.view == :plan}
              id="access-select"
              name={@search_form[:access].name}
              prefix="Access"
              pad="pl-[3.75rem]"
              class="col-span-2 sm:col-span-1 lg:w-52 lg:flex-none"
            >
              <option
                :for={{value, param, label} <- MetricsAccessList.access_options()}
                value={param}
                selected={@filter.access == value}
              >
                {label}
              </option>
            </.prefixed_select>
          </.form>

          <div class="flex flex-wrap items-center gap-2">
            <.variants_switch variants={@filter.variants} example_hue={@example_hue} />
            <.segmented_buttons
              id="dates-switch"
              label="Dates"
              event="dates"
              options={[
                %{
                  id: "dates-relative",
                  label: "Relative dates",
                  value: "relative",
                  pressed?: @filter.dates == :relative
                },
                %{
                  id: "dates-exact",
                  label: "Exact dates",
                  value: "exact",
                  pressed?: @filter.dates == :exact
                }
              ]}
            />
            <div :if={@filter.view == :plan} class="sm:ml-auto">
              <.switch id="show-locked" checked={@filter.locked == :show} event="toggle_locked">
                Show locked
              </.switch>
            </div>
          </div>
        </div>
      </section>

      <div :if={@filter.view == :plan} class="mt-4">
        <.plan_summary
          plan={@plan}
          counts={@counts}
          unit={@unit}
          matching={@filter.q != "" or not is_nil(@filter.category)}
        />
      </div>

      <div
        id="access-note"
        class="mt-4 flex gap-3 rounded-xl border border-base-300 bg-base-200/50 px-4 py-3 text-sm leading-6 text-base-content/80"
      >
        <.icon name="hero-information-circle-mini" class="mt-1 size-4 shrink-0 text-base-content/50" />
        <div class="min-w-0">
          <p data-part="lead" class="font-semibold text-base-content">
            Web app and API access differ.
          </p>
          <ul class="mt-1.5 space-y-1">
            <li class="flex gap-2">
              <.icon
                name="hero-computer-desktop-mini"
                class="mt-1 size-4 shrink-0 text-base-content/50"
              />
              <span data-part="web-app">{@access_note.web_app}</span>
            </li>
            <li class="flex gap-2">
              <.icon name="hero-code-bracket-mini" class="mt-1 size-4 shrink-0 text-base-content/50" />
              <span data-part="api">{@access_note.api}</span>
            </li>
          </ul>
        </div>
      </div>

      <%!-- Always mounted, so screen readers announce the count as it changes. --%>
      <div
        id="metric-count-region"
        aria-live="polite"
        class={[@chips != [] && "mt-6 flex flex-wrap items-center gap-x-4 gap-y-2"]}
      >
        <p :if={@chips != []} id="metric-count" class="text-sm text-base-content/80">
          <span class="font-semibold text-base-content">{delimit(@total)}</span>
          of {delimit(@all_total)} {@unit.(@all_total)} match your filters
        </p>
        <div :if={@chips != []} id="active-filters" class="flex flex-wrap items-center gap-2">
          <.link
            :for={chip <- @chips}
            id={chip.id}
            patch={chip.path}
            aria-label={"Remove filter: " <> chip.text}
            class="inline-flex h-7 cursor-pointer items-center gap-1 rounded-full border border-primary/30 bg-primary/10 pl-3 pr-1.5 text-xs font-medium text-[color-mix(in_oklab,var(--color-primary)_75%,var(--color-base-content))] outline-none transition-colors duration-150 hover:bg-primary/20 focus-visible:ring-2 focus-visible:ring-primary"
          >
            {chip.text}<.icon name="hero-x-mark-mini" class="size-3.5 opacity-70" />
          </.link>
          <.link
            :if={@clearable?}
            id="clear-filters"
            patch={path(MetricsAccessList.cleared(@filter))}
            class="ml-1 cursor-pointer text-xs font-medium text-base-content/70 underline-offset-2 hover:text-primary hover:underline"
          >
            Clear all
          </.link>
        </div>
      </div>

      <%!-- Clips the rounded corners below lg, where the table scrolls sideways;
           from lg it must not, so the bar legend popover (in the sticky header)
           can overlay past the card's edge. --%>
      <div>
        <div class={[
          "overflow-clip rounded-xl border border-base-300 bg-base-100 lg:overflow-visible",
          if(@chips != [], do: "mt-3", else: "mt-6")
        ]}>
          <%!-- Sticky table headers need an ancestor that does not scroll: the table
             scrolls sideways only below lg, where it is wider than the page. The
             card clips (overflow: clip), which is not a scroll container. --%>
          <div class="overflow-x-auto lg:overflow-visible">
            <table
              :if={@filter.view == :plan}
              id="plan-table"
              class="w-full text-left md:min-w-[54rem]"
            >
              <thead class={sticky_thead()}>
                <.caption_row colspan={4} today={@today}>
                  Access on {@plan.label}, in Sanbase and via the API
                </.caption_row>
                <tr>
                  <th
                    id="th-metric"
                    scope="col"
                    aria-sort={aria_sort(@filter, :metric)}
                    class={["px-3 py-2 align-bottom font-medium md:px-4", header_cell()]}
                  >
                    <.sort_link
                      id="sort-metric"
                      path={path(MetricsAccessList.sorted_by(@filter, :metric))}
                      dir={sort_dir(@filter, :metric)}
                    >
                      Metric
                    </.sort_link>
                  </th>
                  <th
                    id="th-category"
                    scope="col"
                    aria-sort={aria_sort(@filter, :category)}
                    class={["hidden px-4 py-2 align-bottom font-medium md:table-cell", header_cell()]}
                  >
                    <.sort_link
                      id="sort-category"
                      path={path(MetricsAccessList.sorted_by(@filter, :category))}
                      dir={sort_dir(@filter, :category)}
                    >
                      Category
                    </.sort_link>
                  </th>
                  <th
                    :for={channel <- @channels}
                    id={"th-#{channel.key}"}
                    scope="col"
                    aria-sort={aria_sort(@filter, channel.key)}
                    class={["px-3 py-2 text-center align-bottom font-medium md:px-4", header_cell()]}
                  >
                    <.sort_link
                      id={"sort-#{channel.key}"}
                      path={path(MetricsAccessList.sorted_by(@filter, channel.key))}
                      dir={sort_dir(@filter, channel.key)}
                      center?={true}
                    >
                      {channel.label}
                    </.sort_link>
                  </th>
                </tr>
              </thead>
              <tbody id="plan-metric-rows" phx-update="stream">
                <.metric_row
                  :for={{_dom_id, item} <- @streams.rows}
                  item={item}
                  channels={@channels}
                  dates={@filter.dates}
                  today={@today}
                />
              </tbody>
            </table>

            <table
              :if={@filter.view == :compare}
              id="compare-table"
              class="w-full min-w-[48rem] text-left"
            >
              <thead class={sticky_thead()}>
                <.caption_row colspan={length(@plans) + 1} today={@today}>
                  Every plan, via the <.channel_word channel={@filter.channel} />
                  {if @filter.channel == :sanbase, do: " web app"}
                </.caption_row>
                <tr>
                  <th
                    id="th-metric"
                    scope="col"
                    data-sticky="true"
                    aria-sort={aria_sort(@filter, :metric)}
                    class={["px-3 py-2 align-bottom font-medium md:px-4", sticky_header_cell()]}
                  >
                    <.sort_link
                      id="sort-metric"
                      path={path(MetricsAccessList.sorted_by(@filter, :metric))}
                      dir={sort_dir(@filter, :metric)}
                    >
                      Metric
                    </.sort_link>
                  </th>
                  <th
                    :for={plan <- @plans}
                    id={"compare-plan-#{plan.key}"}
                    scope="col"
                    data-plan={plan.key}
                    aria-sort={aria_sort(@filter, {:plan, plan.key})}
                    class={["px-3 py-2 text-center align-bottom font-medium", header_cell()]}
                  >
                    <.sort_link
                      id={"compare-plan-link-#{plan.key}"}
                      path={path(MetricsAccessList.sorted_by(@filter, {:plan, plan.key}))}
                      dir={sort_dir(@filter, {:plan, plan.key})}
                      center?={true}
                    >
                      {plan.label}
                    </.sort_link>
                    <span
                      id={"compare-count-#{plan.key}"}
                      class="mt-0.5 block whitespace-nowrap text-[11px] font-normal text-base-content/70"
                    >
                      {if @filter.channel == :api, do: "via", else: "in"}
                      <.channel_word channel={@filter.channel} />
                      · {delimit(@plan_counts[plan.key])} included
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody id="compare-metric-rows" phx-update="stream">
                <.compare_row
                  :for={{_dom_id, item} <- @streams.rows}
                  item={item}
                  dates={@filter.dates}
                  today={@today}
                />
              </tbody>
            </table>
          </div>

          <div :if={@total == 0} id="metric-empty" class="px-6 py-12 text-center">
            <p class="text-sm text-base-content/70">
              <%= cond do %>
                <% @filter.q != "" -> %>
                  No metric matches “{@filter.q}”. Search looks at technical and display names.
                <% @chips != [] -> %>
                  No metrics match your filters.
                <% true -> %>
                  No metrics to show.
              <% end %>
            </p>
            <.link
              :if={@clearable?}
              id="empty-clear-filters"
              patch={path(MetricsAccessList.cleared(@filter))}
              class="mt-3 inline-block text-sm font-medium text-primary hover:underline"
            >
              Clear filters
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
              class="cursor-pointer rounded-lg border border-base-300 px-4 py-1.5 text-sm font-medium outline-none transition-colors duration-150 hover:bg-base-200 focus-visible:ring-2 focus-visible:ring-primary phx-click-loading:opacity-60"
            >
              Show more
              <span class="tabular-nums text-base-content/70">
                ({delimit(@total - @shown)} left)
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## Count line and chips

  # One chip per filter narrowing the list, each linking to the URL without it.
  defp chips(filter, categories, locked_hidden) do
    access_label =
      Enum.find_value(MetricsAccessList.access_options(), fn {value, _, label} ->
        value == filter.access && label
      end)

    category_name =
      Enum.find_value(categories, fn category ->
        category.slug == filter.category && category.name
      end)

    [
      filter.q != "" &&
        %{id: "chip-search", text: ~s(Search: "#{filter.q}"), path: path(%{filter | q: ""})},
      filter.category &&
        %{
          id: "chip-category",
          text: "Category: #{category_name}",
          path: path(%{filter | category: nil})
        },
      filter.access != :all &&
        %{
          id: "chip-access",
          text: "Access: #{access_label}#{if filter.view == :plan, do: " (Sanbase or API)"}",
          path: path(%{filter | access: :all})
        },
      # An access filter already leaves every locked row out.
      (locked_hidden > 0 and filter.access == :all) &&
        %{id: "chip-locked", text: "Locked hidden", path: path(%{filter | locked: :show})}
    ]
    |> Enum.filter(& &1)
  end

  # The direction a header's indicator shows: nil unless it is the sort column.
  defp sort_dir(%{sort: sort, dir: dir}, sort), do: dir
  defp sort_dir(_filter, _sort), do: nil

  defp aria_sort(filter, sort) do
    case sort_dir(filter, sort) do
      :asc -> "ascending"
      :desc -> "descending"
      nil -> nil
    end
  end

  defp unit_fun(:collapsed), do: fn count -> if count == 1, do: "metric", else: "metrics" end

  defp unit_fun(:expanded),
    do: fn count -> if count == 1, do: "metric variant", else: "metric variants" end

  ## Stream items

  defp item({row, matched}, %{view: :plan} = filter, hues) do
    access = %{sanbase: row.access[{filter.plan, :sanbase}], api: row.access[{filter.plan, :api}]}

    row
    |> base_item(matched)
    |> Map.merge(%{
      category: row.category,
      group: row.group,
      hue: Map.get(hues, row.category, "other"),
      access: access,
      locked?: Enum.all?(Map.values(access), &MetricsAccessList.locked?/1)
    })
  end

  defp item({row, matched}, %{view: :compare} = filter, _hues) do
    cells =
      for %{key: plan} <- PlanMetricAccess.plans(), do: {plan, row.access[{plan, filter.channel}]}

    # Its own ids, so no row of one view is ever patched into the other.
    row
    |> base_item(matched)
    |> Map.merge(%{id: "compare-metric-#{row.id}", cells: cells})
  end

  defp base_item(row, matched) do
    [primary | variants] = MetricsAccessList.sort_variants(row.metrics)

    %{
      id: "metric-#{row.id}",
      name: row.name,
      primary: primary,
      variants: variants,
      # Listed inline only when the search picks out some of the names; when every
      # name matches, the row as a whole is the match.
      matched: if(length(matched) < length(row.metrics), do: matched, else: [])
    }
  end

  ## Summary and category options

  # Per channel: how many rows the plan includes, and for the rest, which plan
  # unlocks them - the lowest listed plan. Rows no listed plan unlocks count as
  # locked, with no plan named (the page does not sell custom plans).
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

  # Plan key => how many rows it includes in the channel.
  defp plan_counts(rows, channel) do
    Map.new(PlanMetricAccess.plans(), fn %{key: plan} ->
      {plan, Enum.count(rows, &(not MetricsAccessList.locked?(&1.access[{plan, channel}])))}
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
    for %{key: key, label: label} <- PlanMetricAccess.plans(),
        count = Map.get(locked, key),
        do: %{id: key, count: count, text: if(count == 1, do: "needs ", else: "need ") <> label}
  end

  # Every category on the page, in taxonomy order, counting the rows every other
  # filter keeps. A category the filters empty stays listed with 0.
  defp category_options(rows, counts) do
    rows
    |> Enum.uniq_by(& &1.category)
    |> Enum.map(
      &%{slug: &1.category_slug, name: &1.category, count: Map.get(counts, &1.category, 0)}
    )
  end
end

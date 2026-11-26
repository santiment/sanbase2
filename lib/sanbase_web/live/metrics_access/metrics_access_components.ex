defmodule SanbaseWeb.MetricsAccessComponents do
  @moduledoc """
  Building blocks of the public metrics-by-plan page (`SanbaseWeb.MetricsAccessLive`):
  the toolbar controls, the stat cards, the two-segment access bar and the cells
  and rows of the plan and compare tables.

  The access bar has two equal halves, history on the left and delay on the
  right. Each half shows a state, never an amount: green when unlimited, amber
  (history) or red (delay) when limited, empty with a lock when locked.
  """
  use SanbaseWeb, :html

  alias Sanbase.Billing.Plan.PlanMetricAccess
  alias SanbaseWeb.MetricsAccessFormat

  # Limited history is amber, a delay is red. The theme's `warning` is an
  # orange-red next to `error`, so amber comes from the Tailwind palette. The
  # text under a bar is never coloured: the bar carries the state.
  @amber_fill "bg-amber-500"

  # Category hues, assigned by taxonomy position. Kept apart from the access
  # bar's green / amber / red. The breadcrumb's left edge and the arrow into the
  # group take the hue at full strength.
  @hues [
    %{
      key: "indigo",
      edge: "border-l-indigo-500",
      arrow: "text-indigo-500",
      tint: "bg-indigo-500/15"
    },
    %{key: "teal", edge: "border-l-teal-500", arrow: "text-teal-500", tint: "bg-teal-500/15"},
    %{
      key: "fuchsia",
      edge: "border-l-fuchsia-500",
      arrow: "text-fuchsia-500",
      tint: "bg-fuchsia-500/15"
    },
    %{key: "sky", edge: "border-l-sky-500", arrow: "text-sky-500", tint: "bg-sky-500/15"},
    %{
      key: "violet",
      edge: "border-l-violet-500",
      arrow: "text-violet-500",
      tint: "bg-violet-500/15"
    },
    %{key: "cyan", edge: "border-l-cyan-500", arrow: "text-cyan-500", tint: "bg-cyan-500/15"},
    %{key: "blue", edge: "border-l-blue-500", arrow: "text-blue-500", tint: "bg-blue-500/15"},
    %{
      key: "purple",
      edge: "border-l-purple-500",
      arrow: "text-purple-500",
      tint: "bg-purple-500/15"
    }
  ]
  @other_hue %{
    key: "other",
    edge: "border-l-base-content/25",
    arrow: "text-base-content/40",
    tint: "bg-base-content/10"
  }

  @doc """
  Category name => hue key, by position among the categories of `rows` (already
  in taxonomy order). "Other" has no hue.
  """
  @spec category_hues([map()]) :: %{String.t() => String.t()}
  def category_hues(rows) do
    rows
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == "Other"))
    |> Enum.with_index()
    |> Map.new(fn {category, index} ->
      {category, Enum.at(@hues, rem(index, length(@hues))).key}
    end)
  end

  ## Toolbar

  @doc """
  The bar that sticks to the top of the viewport: one control picking a plan
  (the plan view) or Compare all plans (the compare view), and the channel
  control. The plan view shows both channels, so there the channel control only
  says so; in the compare view it is the toggle between them, coloured so it
  cannot be missed.
  """
  attr :plans, :list, required: true
  attr :view, :atom, required: true
  attr :selected, :string, required: true, doc: "the plan of the plan view"
  attr :channel, :atom, required: true
  attr :plan_path, :any, required: true, doc: "plan key => URL"
  attr :compare_path, :string, required: true
  attr :channel_path, :any, required: true, doc: "channel => URL"

  def plan_bar(assigns) do
    ~H"""
    <div
      id="plan-bar"
      phx-hook="PlanBarHeight"
      class="sticky top-[env(safe-area-inset-top,0px)] z-30 -mx-1 bg-base-100 px-1 pt-3 pb-2"
    >
      <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 rounded-xl border border-base-300 bg-base-100 px-4 py-3 shadow-sm">
        <div class="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-2 max-md:w-full max-md:flex-nowrap">
          <span id="plan-label" class="text-sm font-semibold">Plan</span>
          <nav
            id="plan-picker"
            aria-labelledby="plan-label"
            class={
              [
                "flex flex-wrap items-stretch gap-0.5 rounded-lg border border-base-300 bg-base-200 p-0.5",
                # Below md: one row that scrolls sideways, without a scrollbar.
                "max-md:min-w-0 max-md:flex-nowrap max-md:overflow-x-auto",
                "max-md:[scrollbar-width:none] max-md:[&::-webkit-scrollbar]:hidden"
              ]
            }
          >
            <.link
              :for={plan <- @plans}
              id={"plan-#{plan.key}"}
              patch={@plan_path.(plan.key)}
              aria-current={(@view == :plan and plan.key == @selected) && "true"}
              title={includes(plan.includes)}
              class={plan_option_class(@view == :plan and plan.key == @selected)}
            >
              {plan.label}
            </.link>
            <span aria-hidden="true" class="mx-0.5 my-1.5 hidden w-px shrink-0 bg-base-300 xl:block" />
            <.link
              id="view-compare"
              patch={@compare_path}
              aria-current={@view == :compare && "true"}
              class={plan_option_class(@view == :compare)}
            >
              <.icon name="hero-squares-2x2-mini" class="mr-1.5 size-4" /> Compare all plans
            </.link>
          </nav>
        </div>

        <%!-- The plan view's channel line is informational: hidden below md. --%>
        <div class={[
          "flex flex-wrap items-center gap-x-3 gap-y-2",
          @view == :plan && "max-md:hidden"
        ]}>
          <span id="channel-label" class="text-sm text-base-content/70">
            {if @view == :compare, do: "Showing access via", else: "Showing access in"}
          </span>
          <%= if @view == :compare do %>
            <nav
              id="channel-switch"
              data-mode="toggle"
              aria-label="Channel"
              class="flex h-10 items-stretch gap-1 rounded-lg border border-base-300 bg-base-100 p-0.5"
            >
              <.link
                :for={option <- channel_options()}
                id={"channel-#{option.key}"}
                patch={@channel_path.(option.key)}
                aria-current={@channel == option.key && "true"}
                class={[
                  "inline-flex cursor-pointer items-center gap-2 whitespace-nowrap rounded-md px-4 text-sm font-semibold outline-none",
                  "transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-offset-1",
                  option.ring,
                  if(@channel == option.key,
                    do: [
                      option.active,
                      "text-white shadow-sm motion-safe:animate-pulse motion-safe:[animation-iteration-count:2]"
                    ],
                    else: "text-base-content/80 hover:bg-base-200 hover:text-base-content"
                  )
                ]}
              >
                <span
                  :if={@channel != option.key}
                  aria-hidden="true"
                  class={["size-2 rounded-full", option.dot]}
                />
                {option.label}
              </.link>
            </nav>
          <% else %>
            <div
              id="channel-switch"
              data-mode="both"
              title="This view shows both"
              class="flex h-10 cursor-default items-stretch gap-1 rounded-lg border border-base-300 bg-base-200 p-0.5"
            >
              <span
                :for={option <- channel_options()}
                id={"channel-#{option.key}"}
                class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-md bg-base-100 px-3 text-sm font-medium text-base-content/80 shadow-sm"
              >
                <.icon name="hero-check-mini" class="size-4 text-success" />
                {option.label}
              </span>
              <span class="sr-only">This view shows both channels</span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Each channel's own hue, from the category palette (not the access colours).
  # White text on the filled option is >= 4.5:1 (violet-600, sky-700).
  defp channel_options() do
    [
      %{
        key: :sanbase,
        label: "Sanbase",
        active: "bg-violet-600",
        dot: "bg-violet-500",
        ring: "focus-visible:ring-violet-600"
      },
      %{
        key: :api,
        label: "API",
        active: "bg-sky-700",
        dot: "bg-sky-500",
        ring: "focus-visible:ring-sky-700"
      }
    ]
  end

  defp plan_option_class(current?) do
    [
      "inline-flex h-9 cursor-pointer items-center whitespace-nowrap rounded-md px-3 text-sm outline-none max-md:shrink-0",
      "transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-primary",
      if(current?,
        do: "bg-primary font-semibold text-primary-content shadow-sm",
        else: "text-base-content/80 hover:bg-base-100 hover:text-base-content"
      )
    ]
  end

  @doc """
  A segmented control of buttons sending `event` with `%{"option" => value}`.

  The option travels under its own key: LiveView's client also puts a button's
  `value` property in the payload as "value" (an empty string when the button
  has none), which would overwrite a `phx-value-value`. Each button also carries
  its option as its real `value`.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :options, :list, required: true, doc: "`%{id, label, value, pressed?}`"
  attr :describedby, :string, default: nil

  def segmented_buttons(assigns) do
    ~H"""
    <div id={@id} role="group" aria-label={@label} class={["flex h-9 items-stretch", segmented_box()]}>
      <button
        :for={option <- @options}
        id={option.id}
        type="button"
        phx-click={@event}
        value={option.value}
        phx-value-option={option.value}
        aria-describedby={@describedby}
        aria-pressed={to_string(option.pressed?)}
        class={segment_class(option.pressed?)}
      >
        {option.label}
      </button>
    </div>
    """
  end

  defp segmented_box(), do: "gap-0.5 rounded-lg border border-base-300 bg-base-200 p-0.5"

  defp segment_class(current?) do
    [
      "inline-flex cursor-pointer items-center whitespace-nowrap rounded-md px-2.5 text-sm outline-none",
      "transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-primary",
      if(current?,
        do: "bg-base-100 font-medium text-base-content shadow-sm",
        else: "text-base-content/70 hover:text-base-content"
      )
    ]
  end

  @doc "A native select with an inline prefix label and its own chevron."
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :prefix, :string, required: true
  attr :pad, :string, required: true, doc: "left padding class clearing the prefix"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def prefixed_select(assigns) do
    ~H"""
    <div class={["relative min-w-0", @class]}>
      <label
        for={@id}
        class="pointer-events-none absolute inset-y-0 left-3 flex items-center text-xs font-medium text-base-content/60"
      >
        {@prefix}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          "h-9 w-full cursor-pointer appearance-none rounded-lg border border-base-300 bg-base-100 pr-8 text-sm outline-none",
          "transition-colors duration-150 hover:border-base-content/30 focus:border-primary focus:ring-2 focus:ring-primary/20",
          @pad
        ]}
      >
        {render_slot(@inner_block)}
      </select>
      <.icon
        name="hero-chevron-up-down-mini"
        class="pointer-events-none absolute right-2.5 top-1/2 size-4 -translate-y-1/2 text-base-content/50"
      />
    </div>
    """
  end

  @doc "On/off switch: a track with a knob."
  attr :id, :string, required: true
  attr :checked, :boolean, required: true
  attr :event, :string, required: true
  slot :inner_block, required: true

  def switch(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="switch"
      aria-checked={to_string(@checked)}
      phx-click={@event}
      class="group inline-flex h-9 cursor-pointer items-center gap-2 rounded-lg px-1 text-sm outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <span class={[
        "relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors duration-150",
        if(@checked, do: "bg-primary", else: "bg-base-content/20 group-hover:bg-base-content/30")
      ]}>
        <span class={[
          "absolute left-0.5 size-4 rounded-full bg-base-100 shadow-sm transition-transform duration-150",
          @checked && "translate-x-4"
        ]} />
      </span>
      <span class="whitespace-nowrap text-base-content/80">{render_slot(@inner_block)}</span>
    </button>
    """
  end

  @variant_examples [
    {"_1h", "the last hour"},
    {"_24h", "the last 24 hours"},
    {"_7d", "the last 7 days"}
  ]

  @doc """
  Collapse / Expand variants. Hovering the control (either option or the icon)
  or keyboard focus on the icon opens a small explainer under it, after a short
  delay so passing over it does not flash it; it closes at once. Clicking an
  option does not keep it open; Esc on the icon closes it (focus moves to the
  first option).
  """
  attr :variants, :atom, required: true
  attr :example_hue, :string, required: true, doc: "the hue key of the On-chain category"

  def variants_switch(assigns) do
    hue = Enum.find(@hues, @other_hue, &(&1.key == assigns.example_hue))
    assigns = assign(assigns, tint: hue.tint, examples: @variant_examples)

    ~H"""
    <div class="group/variants relative flex items-center gap-1">
      <.segmented_buttons
        id="variants-switch"
        label="Variants"
        event="variants"
        describedby="variants-help-tooltip"
        options={[
          %{
            id: "variants-collapsed",
            label: "Collapse variants",
            value: "collapsed",
            pressed?: @variants == :collapsed
          },
          %{
            id: "variants-expanded",
            label: "Expand variants",
            value: "expanded",
            pressed?: @variants == :expanded
          }
        ]}
      />
      <button
        id="variants-help"
        type="button"
        aria-describedby="variants-help-tooltip"
        class="peer inline-flex size-7 cursor-pointer items-center justify-center rounded-full text-base-content/50 outline-none transition-colors duration-150 hover:text-base-content focus-visible:ring-2 focus-visible:ring-primary"
      >
        <.icon name="hero-information-circle-mini" class="size-4" />
        <span class="sr-only">About variants</span>
      </button>
      <div
        id="variants-help-tooltip"
        role="tooltip"
        data-dismiss="escape"
        class={
          [
            "invisible absolute left-0 top-full z-40 mt-3 w-[300px] max-w-[calc(100vw-2rem)]",
            # Covers the gap above it, so the pointer can move onto it without
            # leaving the hover (invisible, it takes no pointer events).
            "before:absolute before:inset-x-0 before:-top-3 before:h-3 before:content-['']",
            # Esc dismisses it (app.js) until the pointer leaves or focus moves.
            "data-dismissed:invisible! data-dismissed:opacity-0!",
            "rounded-xl border border-base-300 bg-base-100 p-3.5 text-base-content opacity-0 shadow-xl",
            "transition-opacity duration-0",
            "group-hover/variants:visible group-hover/variants:opacity-100 group-hover/variants:delay-150 group-hover/variants:duration-150",
            "peer-focus-visible:visible peer-focus-visible:opacity-100",
            "motion-reduce:transition-none"
          ]
        }
      >
        <span
          aria-hidden="true"
          class="absolute -top-1.5 left-10 size-3 rotate-45 border-l border-t border-base-300 bg-base-100"
        />
        <p data-part="title" class="text-sm font-semibold">What are variants?</p>
        <p data-part="summary" class="mt-1 text-xs leading-5 text-base-content/70">
          The same measurement computed over different time windows, listed as one row.
        </p>
        <div class="mt-2.5 rounded-lg bg-base-200/60 p-2.5">
          <p data-part="base" class="font-mono text-xs font-semibold">active_addresses</p>
          <ul class="mt-1.5 space-y-1">
            <li
              :for={{suffix, window} <- @examples}
              data-example={suffix}
              class="flex items-center gap-2 text-xs"
            >
              <code class={[
                "w-11 shrink-0 rounded px-1.5 py-0.5 text-center font-mono text-[11px]",
                @tint
              ]}>
                {suffix}
              </code>
              <span class="text-base-content/70">unique addresses active in {window}</span>
            </li>
          </ul>
        </div>
        <p data-part="footer" class="mt-2.5 text-xs text-base-content/70">
          Expand variants to list each one as its own row.
        </p>
      </div>
    </div>
    """
  end

  ## Table headers

  @doc """
  A sortable column header's link, with an indicator: up/down chevrons, muted,
  when the column is not the sort; one chevron in its direction when it is.
  """
  attr :id, :string, required: true
  attr :path, :string, required: true
  attr :dir, :atom, default: nil, doc: "nil, or :asc / :desc when this is the sort column"
  attr :center?, :boolean, default: false
  attr :wrap?, :boolean, default: false, doc: "the label may wrap (narrow columns)"
  slot :inner_block, required: true

  def sort_link(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@path}
      class={[
        "group/sort -mx-1 inline-flex max-w-full cursor-pointer items-center gap-1 rounded px-1 py-0.5 outline-none",
        if(@wrap?, do: "text-balance", else: "whitespace-nowrap"),
        "transition-colors duration-150 hover:bg-base-300/60 hover:text-base-content focus-visible:ring-2 focus-visible:ring-primary",
        @dir && "text-base-content",
        @center? && "justify-center"
      ]}
    >
      {render_slot(@inner_block)}
      <.icon
        name={
          case @dir do
            :asc -> "hero-chevron-up-mini"
            :desc -> "hero-chevron-down-mini"
            nil -> "hero-chevron-up-down-mini"
          end
        }
        class={
          if(@dir,
            do: "size-3.5 shrink-0 text-primary",
            else: "size-3.5 shrink-0 opacity-40 group-hover/sort:opacity-80"
          )
        }
      />
    </.link>
    """
  end

  ## Summary

  @doc """
  Per channel: how many metrics the selected plan includes, with what unlocks the
  rest. The Sanbase card of a Business plan names the Sanbase plan it includes.
  """
  attr :plan, :map, required: true
  attr :counts, :list, required: true, doc: "`%{key, label, included, total, missing}`"
  attr :unit, :any, required: true, doc: "count => \"metrics\" or \"metric variants\""

  attr :matching, :boolean,
    default: false,
    doc: "a search or category narrows the counts: they say \"matching\""

  attr :api_limits, :map, required: true, doc: "the plan's `api_call_limits/1`"

  def plan_summary(assigns) do
    ~H"""
    <div id="plan-summary" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <div
        :for={count <- @counts}
        id={"summary-#{count.key}"}
        class="min-w-0 rounded-xl border border-base-300 bg-base-100 px-4 py-3 shadow-sm"
      >
        <div class="flex items-center justify-between gap-2">
          <span class="min-w-0 truncate text-sm text-base-content/70">
            Included {lowercase_first(count.label)}
          </span>
          <span
            :if={count.key == :sanbase && @plan.includes}
            id="summary-sanbase-includes"
            class="shrink-0 whitespace-nowrap rounded-full bg-base-200 px-2 py-0.5 text-xs font-medium text-base-content/80"
          >
            {includes(@plan.includes)}
          </span>
        </div>
        <div class="mt-0.5 flex flex-wrap items-baseline gap-x-1">
          <span class="text-2xl font-bold tabular-nums">{delimit(count.included)}</span>
          <span class="text-sm text-base-content/70">
            of {delimit(count.total)} {if @matching, do: "matching"} {@unit.(count.total)}
          </span>
        </div>
        <div class="mt-0.5 text-xs text-base-content/70">
          <%= if count.included == count.total do %>
            Everything included
          <% else %>
            <span
              :for={{missing, index} <- Enum.with_index(count.missing)}
              id={"summary-#{count.key}-locked-#{missing.id}"}
            >
              {if index > 0, do: " · "}{delimit(missing.count)} {missing.text}
            </span>
          <% end %>
        </div>
      </div>
      <.api_calls_card plan={@plan} limits={@api_limits} />
    </div>
    """
  end

  # API plans' own hues, a ramp from Sanbase Max to Business Max (apart from the
  # access colours). Text on these tints stays base-content.
  @api_hues %{
    "sanbase_max" => %{
      key: "indigo",
      card: "border-indigo-500/30 bg-indigo-500/[0.06]",
      chip: "bg-indigo-500/15",
      pill: "bg-indigo-500/15"
    },
    "business_pro" => %{
      key: "purple",
      card: "border-purple-500/30 bg-purple-500/[0.06]",
      chip: "bg-purple-500/15",
      pill: "bg-purple-500/15"
    },
    "business_max" => %{
      key: "pink",
      card: "border-pink-500/30 bg-pink-500/[0.06]",
      chip: "bg-pink-500/15",
      pill: "bg-pink-500/15"
    }
  }

  # The plan view's API calls card: the monthly allowance, with per-hour and
  # per-minute limits; plans not meant for the API say so instead.
  attr :plan, :map, required: true
  attr :limits, :map, required: true

  defp api_calls_card(assigns) do
    assigns = assign(assigns, hue: Map.get(@api_hues, assigns.plan.key))

    ~H"""
    <div
      id="summary-api-calls"
      role="group"
      aria-label={@hue && "API calls: " <> MetricsAccessFormat.api_limits_label(@limits)}
      data-hue={@hue && @hue.key}
      class={[
        "min-w-0 rounded-xl border px-4 py-3 shadow-sm",
        if(@hue, do: @hue.card, else: "border-base-300 bg-base-100")
      ]}
    >
      <div class="text-sm text-base-content/70">API calls</div>
      <%= if @hue do %>
        <div data-part="month" class="mt-0.5 flex items-baseline gap-x-1">
          <span class="text-2xl font-bold tabular-nums">
            {MetricsAccessFormat.compact_count(@limits.month)}
          </span>
          <span class="text-sm text-base-content/70">{" / month"}</span>
        </div>
        <div class="mt-1 flex flex-wrap gap-1.5 text-xs tabular-nums">
          <span data-part="hour" class={["rounded-md px-1.5 py-0.5", @hue.chip]}>
            {MetricsAccessFormat.compact_count(@limits.hour)} / hour
          </span>
          <span data-part="minute" class={["rounded-md px-1.5 py-0.5", @hue.chip]}>
            {MetricsAccessFormat.compact_count(@limits.minute)} / min
          </span>
        </div>
      <% else %>
        <p class="mt-2 flex items-center gap-1.5 text-sm text-base-content/70">
          <.icon name="hero-no-symbol-mini" class="size-4 shrink-0 text-base-content/50" />
          Not meant for API access
        </p>
      <% end %>
    </div>
    """
  end

  @doc """
  A compare-view plan header's API limits pill (API channel only): monthly and
  per-minute calls, the full numbers in its title; "Not for API" for plans not
  meant for it. Wraps to two lines in a narrow column.
  """
  attr :plan, :string, required: true
  attr :limits, :map, required: true

  def api_limits_pill(assigns) do
    assigns = assign(assigns, hue: Map.get(@api_hues, assigns.plan))

    ~H"""
    <span
      id={"compare-limits-#{@plan}"}
      title={@hue && MetricsAccessFormat.api_limits_label(@limits)}
      class={[
        "mt-1 inline-flex flex-wrap justify-center gap-x-1 rounded-md px-1.5 py-0.5 text-[10px] font-medium leading-4",
        if(@hue, do: [@hue.pill, "text-base-content"], else: "bg-base-content/5 text-base-content/60")
      ]}
    >
      <%= if @hue do %>
        <span class="whitespace-nowrap">{MetricsAccessFormat.compact_count(@limits.month)}/mo</span>
        <%!-- Spaces inside the dot keep the text readable when copied; a flex
             item trims them on screen. --%>
        <span aria-hidden="true">{" · "}</span>
        <span class="whitespace-nowrap">{MetricsAccessFormat.compact_count(@limits.minute)}/min</span>
      <% else %>
        Not for API
      <% end %>
    </span>
    """
  end

  ## Access bar and cells

  @doc """
  The two-segment bar of one access value, one size everywhere on the page:
  64 x 8px, two fully rounded halves 4px apart. `role="img"`, labelled with the
  full text; `data-state`, `data-history` and `data-delay` name what it shows.
  With `highlight`, only that half keeps its colour (the legend's swatches).
  """
  attr :access, :any, required: true
  attr :label, :string, required: true
  attr :highlight, :atom, default: nil, values: [nil, :history, :delay]

  def access_bar(assigns) do
    assigns = assign(assigns, bar_state(assigns.access))

    ~H"""
    <span
      role="img"
      aria-label={@label}
      data-state={@state}
      data-history={@history}
      data-delay={@delay}
      data-highlight={@highlight}
      class="relative inline-grid w-16 shrink-0 grid-cols-2 gap-1 align-middle"
      style="grid-template-columns: 1fr 1fr"
    >
      <span class={[
        "block h-2 rounded-full",
        if(@highlight == :delay,
          do: "bg-base-content/15",
          else: fill(@state, @history, :history)
        )
      ]} />
      <span class={[
        "block h-2 rounded-full",
        if(@highlight == :history,
          do: "bg-base-content/15",
          else: fill(@state, @delay, :delay)
        )
      ]} />
      <span
        :if={@state == "locked"}
        data-lockmark
        class="absolute left-1/2 top-1/2 flex -translate-x-1/2 -translate-y-1/2 rounded-sm bg-base-100 px-0.5 text-base-content/60"
      >
        <.icon name="hero-lock-closed-mini" class="size-3" />
      </span>
    </span>
    """
  end

  defp bar_state({:window, history, delay}) do
    %{
      state: "window",
      history: if(history, do: "limited", else: "full"),
      delay: if(delay, do: "delayed", else: "none")
    }
  end

  # Locked whether or not a listed plan unlocks it: the page sells no custom plans.
  defp bar_state({:locked, _plan}), do: %{state: "locked", history: nil, delay: nil}

  defp fill("locked", _, _), do: "bg-base-content/10"
  defp fill("window", "full", :history), do: "bg-success"
  defp fill("window", "limited", :history), do: @amber_fill
  defp fill("window", "none", :delay), do: "bg-success"
  defp fill("window", "delayed", :delay), do: "bg-error"

  @doc """
  One channel cell of a plan-view row: the bar with its compact code centered
  under it, and for a cell locked behind a listed plan, that plan on a second
  line. The full wording is the cell's `title` and the bar's label.
  """
  attr :id, :string, required: true
  attr :channel_label, :string, required: true, doc: "shown above the bar below md"
  attr :access, :any, required: true
  attr :dates, :atom, required: true
  attr :today, Date, required: true

  def access_cell(assigns) do
    assigns =
      assign(assigns,
        label: MetricsAccessFormat.label(assigns.access, assigns.dates, assigns.today)
      )

    ~H"""
    <td
      id={@id}
      data-locked={locked?(@access) && "true"}
      data-label={@channel_label}
      title={@label}
      class={
        [
          "px-3 py-2.5 text-center align-middle md:px-4",
          # Below md the row stacks: the channel's name above its bar, from the
          # data-label (no text in the cell, nothing at md and up).
          "max-md:before:mb-1 max-md:before:block max-md:before:text-[10px] max-md:before:font-medium",
          "max-md:before:uppercase max-md:before:tracking-wider max-md:before:text-base-content/60",
          "max-md:before:content-[attr(data-label)]"
        ]
      }
    >
      <.access_glyph access={@access} label={@label} dates={@dates} today={@today} />
      <span
        :if={match?({:locked, plan} when is_binary(plan), @access)}
        aria-hidden="true"
        class="block whitespace-nowrap text-[11px] leading-4 text-base-content/60"
      >
        {MetricsAccessFormat.plan_label(elem(@access, 1))}
      </span>
    </td>
    """
  end

  @doc """
  The bar and its compact code under it, centered as a unit: what every table
  cell shows, and the legend's examples, so they are identical. The code repeats
  the bar's label, so it is hidden from screen readers.
  """
  attr :access, :any, required: true
  attr :label, :string, required: true
  attr :dates, :atom, required: true
  attr :today, Date, required: true
  attr :compact?, :boolean, default: false, doc: ~s(drop "since " from an exact date)

  def access_glyph(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <.access_bar access={@access} label={@label} />
      <%= case MetricsAccessFormat.code_parts(@access, @dates, @today) do %>
        <% {history, delay} -> %>
          <.code_grid
            left={if(@compact?, do: String.replace_prefix(history, "since ", ""), else: history)}
            right={delay}
          />
        <% single -> %>
          <span
            aria-hidden="true"
            data-part="code"
            class="whitespace-nowrap text-xs leading-4 text-base-content/70"
          >
            {if single == :full, do: "Full", else: "Locked"}
          </span>
      <% end %>
    </div>
    """
  end

  # Two texts under the two halves of a bar. A long left text (exact dates)
  # ends at the left half's edge and grows to the left (unsafe end alignment:
  # grid would otherwise fall back to start alignment when it overflows), so it
  # never runs into the right one. The hidden dot
  # keeps the copied text readable.
  attr :left, :string, required: true
  attr :right, :string, required: true
  attr :class, :any, default: "text-xs leading-4 tabular-nums text-base-content/70"

  defp code_grid(assigns) do
    ~H"""
    <span
      aria-hidden="true"
      data-part="code"
      class={["relative grid w-16 grid-cols-2 gap-1", @class]}
      style="grid-template-columns: 1fr 1fr"
    >
      <span class={[
        "whitespace-nowrap",
        if(String.length(@left) > 4,
          do: "[justify-self:unsafe_end] text-right",
          else: "justify-self-center"
        )
      ]}>
        {@left}<span class="sr-only"> · </span>
      </span>
      <span class="justify-self-center whitespace-nowrap">{@right}</span>
    </span>
    """
  end

  @doc "One plan cell of a compare-view row: the bar and its compact code."
  attr :id, :string, required: true
  attr :plan, :string, required: true
  attr :access, :any, required: true
  attr :dates, :atom, required: true
  attr :today, Date, required: true

  def compare_cell(assigns) do
    assigns =
      assign(assigns,
        label: MetricsAccessFormat.label(assigns.access, assigns.dates, assigns.today)
      )

    ~H"""
    <td
      id={@id}
      data-plan={@plan}
      data-locked={locked?(@access) && "true"}
      title={@label}
      class="px-3 py-2.5 text-center align-middle"
    >
      <.access_glyph access={@access} label={@label} dates={@dates} today={@today} />
    </td>
    """
  end

  @doc """
  A cell pinned to the left edge of a horizontally scrolling table, opaque so
  the columns scroll under it, with a hairline on its right. Its background
  follows the row's hover tint.
  """
  def sticky_cell() do
    [
      "sticky left-0 z-10 bg-base-100 shadow-[1px_0_0_var(--color-base-300)]",
      "group-hover:bg-[color-mix(in_oklab,var(--color-base-200)_50%,var(--color-base-100))]"
    ]
  end

  @doc """
  The table header, stuck under the plan bar (`--plan-bar-h`, published by the
  bar's `PlanBarHeight` hook) while the rows scroll. It tucks 1px under the bar,
  so no row ever shows between the two. Above the rows, below the plan bar.
  From md only: below it the table scrolls sideways in its own box, and a
  sticky header would be offset inside that box.
  """
  def sticky_thead() do
    "md:sticky md:top-[calc(var(--plan-bar-h,5.5rem)_+_env(safe-area-inset-top,0px)_-_1px)] md:z-20 text-xs text-base-content/70"
  end

  @doc """
  A column header cell: fully opaque (rows scroll under it), its bottom hairline
  an inset shadow, so it is drawn inside the cell and travels with it.
  """
  def header_cell() do
    "bg-base-200 shadow-[inset_0_-1px_0_var(--color-base-300)]"
  end

  @doc "The header cell over `sticky_cell/0`: also pinned to the left edge."
  def sticky_header_cell() do
    "sticky left-0 z-10 bg-base-200 shadow-[inset_-1px_0_0_var(--color-base-300),inset_0_-1px_0_var(--color-base-300)]"
  end

  @key_states [
    {"full", {:window, nil, nil}},
    {"limited", {:window, 730, nil}},
    {"both", {:window, 365, 30}},
    {"delayed", {:window, nil, 30}},
    {"locked", {:locked, nil}}
  ]

  @doc """
  The caption row of a table's sticky header: what the table shows, a key to the
  bars (the same cells as the table: bar and aligned code) and a "What do these
  mean?" popover with the definitions. Below lg only the label and the button
  show.
  """
  attr :colspan, :integer, required: true
  attr :today, Date, required: true

  attr :block_below_md?, :boolean,
    default: false,
    doc: "below md, a block spanning the table (the plan view's stacked rows)"

  slot :inner_block, required: true

  def caption_row(assigns) do
    assigns = assign(assigns, states: @key_states)

    ~H"""
    <tr class={@block_below_md? && "max-md:block"}>
      <th
        colspan={@colspan}
        class={[
          "relative rounded-t-xl bg-base-100 px-4 py-2 text-left font-normal shadow-[inset_0_-1px_0_var(--color-base-300)]",
          @block_below_md? && "max-md:block"
        ]}
      >
        <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
          <p id="table-caption" class="text-xs text-base-content/70">{render_slot(@inner_block)}</p>
          <div
            id="bar-key"
            class="flex min-w-0 max-w-full flex-wrap items-center justify-end gap-x-4 gap-y-2 text-xs text-base-content/70"
          >
            <span id="bar-key-label" class="whitespace-nowrap">
              Each bar: <span class="font-medium text-base-content/80">History · Delay</span>
            </span>
            <span :for={{key, access} <- @states} data-key={key} class="hidden xl:inline-flex">
              <.access_glyph
                access={access}
                label={MetricsAccessFormat.label(access, :relative, @today)}
                dates={:relative}
                today={@today}
              />
            </span>
            <%!-- Not positioned: the dialog's containing block is the caption cell,
                 so it spans from the cell's right edge. Button and dialog share
                 this wrapper, so a click on the button is not a click away. --%>
            <div phx-click-away={hide_bar_help()}>
              <button
                id="bar-help-button"
                type="button"
                aria-expanded="false"
                aria-controls="bar-help"
                phx-click={toggle_bar_help()}
                class="cursor-pointer whitespace-nowrap rounded text-xs font-medium text-[color-mix(in_oklab,var(--color-primary)_75%,var(--color-base-content))] underline-offset-2 outline-none hover:underline focus-visible:ring-2 focus-visible:ring-primary"
              >
                What do these mean?
              </button>
              <.bar_help today={@today} />
            </div>
          </div>
        </div>
      </th>
    </tr>
    """
  end

  # The "What do these mean?" popover, anchored in the sticky caption cell, so it
  # opens right under the button whether or not the header is stuck, and never
  # changes the page's layout or scroll position: it is absolutely positioned,
  # its height capped to the viewport below the sticky header (scrolling inside),
  # and focus moves without scrolling. The close button or a click outside close
  # it; so does Esc, through app.js, only while it is open (`data-dismiss`), and
  # focus goes back to the button. Below lg it is a bottom sheet.
  attr :today, Date, required: true

  defp bar_help(assigns) do
    ~H"""
    <div
      id="bar-help"
      role="dialog"
      data-dismiss="escape"
      data-on-escape={hide_bar_help()}
      data-return-focus="bar-help-button"
      aria-label="What the bars mean"
      tabindex="-1"
      class={
        [
          "z-40 hidden w-[560px] max-w-[calc(100vw-2rem)] shrink-0 overflow-y-auto rounded-xl border border-base-300 bg-base-100 p-5",
          "text-left font-normal normal-case tracking-normal text-base-content shadow-xl outline-none",
          "absolute right-4 top-full mt-1 [overflow-anchor:none]",
          "max-h-[calc(100vh-var(--plan-bar-h,5.5rem)-8rem)]",
          # Below md: a bottom sheet, clear of the sticky plan bar at the top.
          "max-md:fixed max-md:inset-x-4 max-md:bottom-4 max-md:top-auto max-md:mt-0 max-md:w-auto",
          "max-md:max-h-[calc(100dvh-var(--plan-bar-h,5.5rem)-2rem)]"
        ]
      }
    >
      <span
        aria-hidden="true"
        class="absolute -top-1.5 right-10 hidden size-3 rotate-45 border-l border-t border-base-300 bg-base-100 lg:block"
      />
      <button
        id="bar-help-close"
        type="button"
        aria-label="Close"
        phx-click={hide_bar_help() |> focus_without_scroll("#bar-help-button")}
        class="absolute right-3 top-3 inline-flex size-7 cursor-pointer items-center justify-center rounded-md text-base-content/60 outline-none transition-colors duration-150 hover:bg-base-200 hover:text-base-content focus-visible:ring-2 focus-visible:ring-primary"
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </button>
      <div class="grid gap-6 md:grid-cols-2">
        <.help_section
          term="history"
          title="History — left half"
          definition="How far back the data goes on this plan."
          examples={[
            {"full", {:window, nil, nil}, :relative, "all history, nothing held back"},
            {"2y", {:window, 730, nil}, :relative, "the last 2 years"},
            {"1y", {:window, 365, nil}, :relative, "the last year"},
            {"exact", {:window, 730, nil}, :exact, "exact dates: from that month on"}
          ]}
          today={@today}
        />
        <.help_section
          term="delay"
          title="Delay — right half"
          definition="Whether the plan holds back the newest data."
          examples={[
            {"none", {:window, nil, nil}, :relative,
             "no delay: data up to the latest computed point"},
            {"delayed", {:window, nil, 30}, :relative, "the latest 30 days are held back"}
          ]}
          today={@today}
        />
      </div>

      <div class="mt-4 border-t border-base-300 pt-4">
        <div data-guide="locked" class="grid grid-cols-[64px_1fr] items-center gap-x-4 text-xs">
          <.access_glyph
            access={{:locked, nil}}
            label="Locked"
            dates={:relative}
            today={@today}
          />
          <span class="text-base-content/70">
            Not on this plan — the plan view names the plan that unlocks it
          </span>
        </div>
      </div>

      <p data-part="computation" class="mt-4 flex gap-1.5 text-xs leading-5 text-base-content/60">
        <.icon name="hero-information-circle-mini" class="mt-0.5 size-3.5 shrink-0" />
        <span>
          No delay doesn't mean instant: each metric still has its normal computation time, from minutes to a day.
        </span>
      </p>
    </div>
    """
  end

  # The JS commands set display and aria-expanded on the client, so both survive
  # LiveView's patches.
  defp toggle_bar_help() do
    JS.toggle(to: "#bar-help")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#bar-help-button")
    |> focus_without_scroll("#bar-help")
  end

  # JS.focus would scroll the target into view; app.js focuses on this event
  # with `preventScroll`.
  defp focus_without_scroll(js, selector), do: JS.dispatch(js, "metrics:focus", to: selector)

  defp hide_bar_help() do
    JS.hide(to: "#bar-help")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#bar-help-button")
  end

  attr :term, :string, required: true
  attr :title, :string, required: true
  attr :definition, :string, required: true
  attr :examples, :list, required: true, doc: "`{key, access, dates mode, meaning}`"
  attr :today, Date, required: true

  defp help_section(assigns) do
    ~H"""
    <section data-term={@term}>
      <h3 class="flex items-center gap-3 text-sm font-semibold">
        <.access_bar
          access={{:window, nil, nil}}
          label={@title}
          highlight={String.to_existing_atom(@term)}
        />
        {@title}
      </h3>
      <p data-part="definition" class="mt-1.5 text-sm text-base-content/80">{@definition}</p>
      <ul class="mt-3 grid grid-cols-[64px_1fr] items-center gap-x-4 gap-y-3">
        <li :for={{key, access, mode, meaning} <- @examples} data-example={key} class="contents">
          <.access_glyph
            access={access}
            label={MetricsAccessFormat.label(access, mode, @today)}
            dates={mode}
            today={@today}
            compact?={true}
          />
          <span data-part="meaning" class="text-xs text-base-content/70">{meaning}</span>
        </li>
      </ul>
    </section>
    """
  end

  @doc """
  A channel's name in the compare view, bold in that channel's hue (the same as
  its option in the channel toggle), readable (>= 5.4:1) in both themes.
  """
  attr :channel, :atom, required: true

  def channel_word(assigns) do
    ~H"""
    <span
      data-channel={@channel}
      class={[
        "font-semibold",
        if(@channel == :api,
          do: "text-[color-mix(in_oklab,var(--color-sky-600)_75%,var(--color-base-content))]",
          else: "text-[color-mix(in_oklab,var(--color-violet-500)_75%,var(--color-base-content))]"
        )
      ]}
    >{if @channel == :api, do: "API", else: "Sanbase"}</span>
    """
  end

  ## Rows

  @doc "The metric cell: technical name, display name, variants and search matches."
  attr :item, :map, required: true

  attr :crumb?, :boolean,
    default: false,
    doc: "below lg, the category breadcrumb under the names (the column is hidden)"

  attr :sticky?, :boolean,
    default: false,
    doc: "stays at the left edge while the columns after it scroll"

  def metric_cell(assigns) do
    ~H"""
    <td
      data-sticky={@sticky? && "true"}
      class={
        [
          # Below md the table scrolls sideways, so the column keeps a readable
          # width; from md it takes what the fixed-width columns leave.
          "min-w-[10rem] px-3 py-2.5 align-middle text-sm leading-5 md:min-w-0 md:px-4",
          # Plan view below md: the stacked row's first line, across both columns.
          @crumb? && "max-md:col-span-2 max-md:pb-1",
          @sticky? && sticky_cell()
        ]
      }
    >
      <a
        href={~p"/available_metrics/#{@item.primary}"}
        class="block font-medium underline-offset-2 [overflow-wrap:anywhere] hover:text-primary hover:underline"
      >
        {@item.primary}
      </a>
      <div class="text-xs text-base-content/70">{@item.name}</div>
      <div :if={@crumb?} class="mt-1 lg:hidden">
        <.category_crumb
          id={"#{@item.id}-category-inline"}
          category={@item.category}
          group={@item.group}
          hue={@item.hue}
          small?={true}
        />
      </div>
      <details :if={@item.variants != []} class="group/variants text-xs">
        <summary class="w-fit cursor-pointer list-none text-base-content/70 hover:text-base-content [&::-webkit-details-marker]:hidden">
          +{length(@item.variants)} {if length(@item.variants) == 1,
            do: "variant",
            else: "variants"}
          <.icon
            name="hero-chevron-down-mini"
            class="size-3.5 transition-transform duration-150 group-open/variants:rotate-180"
          />
        </summary>
        <ul class="mt-1 space-y-0.5 break-all text-base-content/70">
          <li :for={variant <- @item.variants}>{variant}</li>
        </ul>
      </details>
      <div :if={@item.matched != []} id={"#{@item.id}-matched"} class="mt-1 text-xs">
        <span class="text-base-content/70">Matches:</span>
        <span :for={metric <- @item.matched} class="ml-1 break-all font-medium text-primary">
          {metric}
        </span>
      </div>
    </td>
    """
  end

  @doc """
  Category and group as one compact breadcrumb on a near-white surface: a left
  edge in the category's hue, the category, then an arrow in the same hue
  leading into the group. Nothing trails the last segment.
  """
  attr :id, :string, required: true
  attr :category, :string, required: true
  attr :group, :string, default: nil
  attr :hue, :string, required: true
  attr :small?, :boolean, default: false

  def category_crumb(assigns) do
    other? = assigns.category == "Other"
    hue = if other?, do: @other_hue, else: Enum.find(@hues, @other_hue, &(&1.key == assigns.hue))

    assigns = assign(assigns, hue: hue, other?: other?)

    ~H"""
    <div
      id={@id}
      role="img"
      aria-label={
        if(@group, do: "Category: #{@category}, group: #{@group}", else: "Category: #{@category}")
      }
      data-hue={@hue.key}
      class={[
        "inline-flex max-w-full items-center gap-1 whitespace-nowrap rounded-md border border-l-2 border-base-300 bg-base-100 pl-2 pr-2.5 leading-none",
        @hue.edge,
        if(@small?, do: "h-[18px] text-[11px]", else: "h-[22px] text-xs")
      ]}
    >
      <span class={
        if(@other?, do: "italic text-base-content/70", else: "font-medium text-base-content")
      }>
        {@category}
      </span>
      <%= if @group && !@other? do %>
        <.icon name="hero-chevron-right-mini" class={"size-3.5 shrink-0 #{@hue.arrow}"} />
        <span class="text-base-content/80">{@group}</span>
      <% end %>
    </div>
    """
  end

  @doc "A metric row of the plan view."
  attr :item, :map, required: true
  attr :channels, :list, required: true
  attr :dates, :atom, required: true
  attr :today, Date, required: true

  def metric_row(assigns) do
    ~H"""
    <tr
      id={@item.id}
      data-kind="row"
      data-locked={@item.locked? && "true"}
      class={[
        "border-b border-base-200 transition-colors duration-150 last:border-b-0 hover:bg-base-200/50",
        "max-md:grid max-md:grid-cols-2",
        @item.locked? && "bg-base-200/40"
      ]}
    >
      <.metric_cell item={@item} crumb?={true} />
      <td class="px-0 py-2.5 align-middle max-md:hidden lg:px-4">
        <div class="hidden lg:block">
          <.category_crumb
            id={"#{@item.id}-category"}
            category={@item.category}
            group={@item.group}
            hue={@item.hue}
          />
        </div>
      </td>
      <.access_cell
        :for={channel <- @channels}
        id={"#{@item.id}-#{channel.key}"}
        channel_label={channel.label}
        access={@item.access[channel.key]}
        dates={@dates}
        today={@today}
      />
    </tr>
    """
  end

  @doc "A metric row of the compare view: one cell per plan, in the chosen channel."
  attr :item, :map, required: true
  attr :dates, :atom, required: true
  attr :today, Date, required: true

  def compare_row(assigns) do
    ~H"""
    <tr
      id={@item.id}
      data-kind="row"
      class="group border-b border-base-200 transition-colors duration-150 last:border-b-0 hover:bg-base-200/50"
    >
      <.metric_cell item={@item} sticky?={true} />
      <.compare_cell
        :for={{plan, access} <- @item.cells}
        id={"#{@item.id}-#{plan}"}
        plan={plan}
        access={access}
        dates={@dates}
        today={@today}
      />
    </tr>
    """
  end

  ## Helpers

  # "Via API" => "via API"
  defp lowercase_first(<<first::utf8, rest::binary>>),
    do: String.downcase(<<first::utf8>>) <> rest

  defp includes(nil), do: nil

  defp includes(plan_key) do
    "Includes " <> Enum.find_value(PlanMetricAccess.plans(), &(&1.key == plan_key && &1.label))
  end

  defp locked?({:locked, _}), do: true
  defp locked?(_), do: false

  @doc "1234567 => \"1,234,567\""
  def delimit(n) when is_integer(n), do: MetricsAccessFormat.delimit(n)
end

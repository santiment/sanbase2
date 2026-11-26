defmodule SanbaseWeb.MetricsAccessComponents do
  @moduledoc """
  Building blocks of the public metrics-by-plan page (`SanbaseWeb.MetricsAccessLive`):
  a filters card, a row of stat cards and a compact table, in the style of the
  metric categorization admin page.
  """
  use SanbaseWeb, :html

  alias Sanbase.Billing.Plan.PlanMetricAccess
  alias SanbaseWeb.MetricsAccessFormat

  @doc "Text-only segmented control of the plans. Each option is a patch link."
  attr :plans, :list, required: true
  attr :selected, :string, required: true
  attr :path_fun, :any, required: true, doc: "plan key => URL"

  def plan_picker(assigns) do
    ~H"""
    <div>
      <p id="plan-picker-label" class="mb-1 text-sm font-semibold">Plan</p>
      <nav
        id="plan-picker"
        aria-labelledby="plan-picker-label"
        class="inline-flex max-w-full flex-wrap gap-1 rounded-lg border border-base-300 bg-base-200 p-1"
      >
        <.link
          :for={plan <- @plans}
          id={"plan-#{plan.key}"}
          patch={@path_fun.(plan.key)}
          aria-current={plan.key == @selected && "true"}
          title={includes(plan.includes)}
          class={[
            "whitespace-nowrap rounded-md px-3 py-1.5 text-sm outline-none",
            "transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-primary",
            if(plan.key == @selected,
              do: "bg-primary font-medium text-primary-content shadow-sm",
              else: "text-base-content/80 hover:bg-base-100 hover:text-base-content"
            )
          ]}
        >
          {plan.label}
        </.link>
      </nav>
    </div>
    """
  end

  @doc "Switch between relative windows (\"Last 2 years\") and calendar dates."
  attr :dates, :atom, required: true

  def date_toggle(assigns) do
    ~H"""
    <div>
      <p id="dates-label" class="mb-1 text-sm font-semibold">Dates</p>
      <div
        role="group"
        aria-labelledby="dates-label"
        class="inline-flex gap-1 rounded-lg border border-base-300 bg-base-200 p-1"
      >
        <.toggle_button id="dates-relative" value="relative" pressed={@dates == :relative}>
          Relative
        </.toggle_button>
        <.toggle_button id="dates-exact" value="exact" pressed={@dates == :exact}>
          Exact
        </.toggle_button>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :pressed, :boolean, required: true
  slot :inner_block, required: true

  defp toggle_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="dates"
      phx-value-dates={@value}
      aria-pressed={to_string(@pressed)}
      class={[
        "rounded-md px-3 py-1.5 text-sm outline-none transition-colors duration-150",
        "focus-visible:ring-2 focus-visible:ring-primary",
        if(@pressed,
          do: "bg-base-100 font-medium text-base-content shadow-sm",
          else: "text-base-content/70 hover:text-base-content"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  The selected plan at a glance: its default windows in each channel, and how many
  of the metrics it includes per channel, with what unlocks the rest.
  """
  attr :plan, :map, required: true, doc: "the selected plan, with `:headlines`"
  attr :channels, :list, required: true
  attr :counts, :list, required: true, doc: "`%{key, label, included, total, missing}`"
  attr :dates, :atom, required: true
  attr :today, Date, required: true

  def plan_summary(assigns) do
    ~H"""
    <div id="plan-summary" aria-live="polite" class="grid grid-cols-2 gap-3 md:grid-cols-4 md:gap-4">
      <.stat_card :for={channel <- @channels} id={"headline-#{channel.key}"} label={channel.label}>
        <:value>
          <span class="text-base font-semibold leading-6 md:text-lg md:leading-7">
            {headline(@plan.headlines[channel.key], @dates, @today)}
          </span>
        </:value>
        <:sub>
          {if channel.key == :sanbase && @plan.includes,
            do: includes(@plan.includes),
            else: "For restricted metrics"}
        </:sub>
      </.stat_card>
      <.stat_card
        :for={count <- @counts}
        id={"summary-#{count.key}"}
        label={"Included " <> lowercase_first(count.label)}
      >
        <:value>
          <span class="text-2xl font-bold tabular-nums">{delimit(count.included)}</span>
          <span class="text-sm text-base-content/70">of {delimit(count.total)}</span>
        </:value>
        <:sub>
          <%= if count.missing == [] do %>
            Everything included
          <% else %>
            <span
              :for={{missing, index} <- Enum.with_index(count.missing)}
              id={"summary-#{count.key}-locked-#{missing.id}"}
            >
              {if index > 0, do: " · "}{delimit(missing.count)} {missing.text}
            </span>
          <% end %>
        </:sub>
      </.stat_card>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :value, required: true
  slot :sub, required: true

  defp stat_card(assigns) do
    ~H"""
    <div id={@id} class="min-w-0 rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
      <div class="text-sm text-base-content/70">{@label}</div>
      <div class="mt-0.5 flex flex-wrap items-baseline gap-x-1">{render_slot(@value)}</div>
      <div class="mt-0.5 text-xs text-base-content/70">{render_slot(@sub)}</div>
    </div>
    """
  end

  @doc "One plan × channel cell of a metric row: plain text."
  attr :id, :string, required: true
  attr :access, :any, required: true
  attr :dates, :atom, required: true
  attr :today, Date, required: true

  def access_cell(assigns) do
    ~H"""
    <td
      id={@id}
      data-locked={locked?(@access) && "true"}
      class="whitespace-nowrap px-4 py-2.5 text-sm leading-5"
    >
      <%= case @access do %>
        <% :free -> %>
          <span class="text-sm font-medium text-success">Free</span>
        <% {:window, history, lag} -> %>
          <span class="text-sm">
            {MetricsAccessFormat.history(history, @dates, @today)}
            <span class="text-base-content/70">· {MetricsAccessFormat.lag(lag, @dates, @today)}</span>
          </span>
        <% {:locked, plan_key} -> %>
          <span class="inline-flex items-center gap-1 text-sm text-base-content/70">
            <.icon name="hero-lock-closed-mini" class="size-3.5 shrink-0" />
            {MetricsAccessFormat.locked(plan_key)}
          </span>
      <% end %>
    </td>
    """
  end

  @doc "A metric row of the table."
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
        "border-b border-base-200 align-top transition-colors duration-150 last:border-b-0 hover:bg-base-200/50",
        @item.locked? && "bg-base-200/40"
      ]}
    >
      <td class="min-w-[15rem] max-w-[22rem] px-4 py-2.5 text-sm leading-5">
        <a
          href={~p"/available_metrics/#{@item.primary}"}
          class="block break-words font-medium underline-offset-2 hover:text-primary hover:underline"
        >
          {@item.primary}
        </a>
        <div class="text-xs text-base-content/70">{@item.name}</div>
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
      <td class="whitespace-nowrap px-4 py-2.5 text-sm leading-5">
        <span :if={@item.category != "Other"}>{@item.category}</span>
        <span :if={@item.category == "Other"} class="text-base-content/70 italic">Other</span>
      </td>
      <td class="whitespace-nowrap px-4 py-2.5 text-sm leading-5">
        <span :if={@item.group}>{@item.group}</span>
        <span :if={!@item.group} class="text-base-content/70">-</span>
      </td>
      <.access_cell
        :for={channel <- @channels}
        id={"#{@item.id}-#{channel.key}"}
        access={@item.access[channel.key]}
        dates={@dates}
        today={@today}
      />
    </tr>
    """
  end

  defp headline({history, lag}, dates, today) do
    MetricsAccessFormat.history(history, dates, today) <>
      " · " <> MetricsAccessFormat.lag(lag, dates, today)
  end

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
  def delimit(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end

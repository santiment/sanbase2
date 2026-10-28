defmodule SanbaseWeb.Admin.AiBotReviewLive do
  @moduledoc """
  Daily review of AI bot turns (Discord and Telegram). Lists the turns that
  were flagged (failed delivery, errors, empty tools, wrong language, down
  votes, slow) and exports them as JSONL for deeper analysis.
  """

  use SanbaseWeb, :live_view

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.AiContextReview

  @default_langfuse_traces_url "http://langfuse.production.san:31080/project/cmkgxdule0006yr077uhnzh1m/traces/"

  @flag_labels %{
    "delivery_failed" => "Delivery failed",
    "error" => "Error",
    "degraded" => "Degraded",
    "tool_issue" => "Tool issue",
    "language_mismatch" => "Wrong language",
    "downvoted" => "Downvoted",
    "slow" => "Slow"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI Bot Review")
     |> assign(:selected, nil)
     |> stream(:rows, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = AiContextReview.parse_filters(params)
    all_rows = AiContextReview.list_for_filters(filters)
    rows = AiContextReview.select(all_rows, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filter_params(filters), as: :filters))
     |> assign(:total_count, length(all_rows))
     |> assign(:shown_count, length(rows))
     |> assign(:flag_counts, AiContextReview.flag_counts(all_rows))
     |> stream(:rows, rows, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/ai_bot_review?#{params}")}
  end

  def handle_event("pick_flag", %{"flag" => flag}, socket) do
    flag = if socket.assigns.filters.flag == flag, do: "", else: flag
    params = socket.assigns.filters |> filter_params() |> Map.put("flag", flag)
    {:noreply, push_patch(socket, to: ~p"/admin/ai_bot_review?#{params}")}
  end

  def handle_event("show", %{"id" => id}, socket) do
    selected =
      case AiContext.by_id(String.to_integer(id)) do
        nil -> nil
        context -> %{context: context, flags: AiContextReview.flags_for(context)}
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  defp filter_params(filters) do
    %{
      "from" => Date.to_iso8601(filters.from),
      "to" => Date.to_iso8601(filters.to),
      "platform" => filters.platform,
      "flag" => filters.flag,
      "flagged_only" => to_string(filters.flagged_only)
    }
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:flags, AiContextReview.flags())
      |> assign(:flag_labels, @flag_labels)
      |> assign(:export_params, filter_params(assigns.filters))

    ~H"""
    <div class="flex flex-col w-full px-4 py-6">
      <div class="flex flex-wrap items-center justify-between gap-4 mb-6">
        <h1 class="text-2xl font-bold">{@page_title}</h1>
        <a
          id="export-jsonl"
          href={~p"/admin/ai_bot_review/export?#{@export_params}"}
          class="btn btn-sm btn-primary"
        >
          <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Download JSONL
        </a>
      </div>

      <.form
        for={@filter_form}
        id="review-filters"
        phx-change="filter"
        class="flex flex-wrap items-end gap-4 mb-4"
      >
        <.input field={@filter_form[:from]} type="date" label="From" outer_div_class="w-40" />
        <.input field={@filter_form[:to]} type="date" label="To" outer_div_class="w-40" />
        <.input
          field={@filter_form[:platform]}
          type="select"
          label="Platform"
          options={[{"All", ""}, {"Discord", "discord"}, {"Telegram", "telegram"}]}
          outer_div_class="w-36"
        />
        <.input
          field={@filter_form[:flag]}
          type="select"
          label="Flag"
          options={[{"Any", ""} | Enum.map(@flags, &{@flag_labels[&1], &1})]}
          outer_div_class="w-44"
        />
        <.input
          field={@filter_form[:flagged_only]}
          type="checkbox"
          label="Flagged only"
          outer_div_class="mb-2"
        />
      </.form>

      <div id="flag-counts" class="flex flex-wrap items-center gap-2 mb-6">
        <span class="text-sm text-base-content/60 mr-2">
          {@shown_count} shown of {@total_count} turns
        </span>
        <button
          :for={flag <- @flags}
          id={"flag-count-#{flag}"}
          type="button"
          phx-click="pick_flag"
          phx-value-flag={flag}
          class={[
            "badge gap-1 cursor-pointer transition-colors",
            if(@filters.flag == flag, do: "badge-neutral", else: "badge-ghost hover:badge-outline")
          ]}
        >
          {@flag_labels[flag]} <span class="font-semibold">{@flag_counts[flag]}</span>
        </button>
      </div>

      <div class="rounded-box border border-base-300 overflow-x-auto">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>Time (UTC)</th>
              <th>Platform</th>
              <th>User</th>
              <th>Question</th>
              <th>Flags</th>
              <th>Seconds</th>
              <th>Trace</th>
            </tr>
          </thead>
          <tbody id="review-rows" phx-update="stream">
            <tr id="review-rows-empty" class="hidden only:table-row">
              <td colspan="7" class="text-center text-base-content/60 py-8">
                Nothing to review in this range.
              </td>
            </tr>
            <tr :for={{dom_id, row} <- @streams.rows} id={dom_id}>
              <td class="whitespace-nowrap">
                {Calendar.strftime(row.context.inserted_at, "%Y-%m-%d %H:%M")}
              </td>
              <td>{AiContextReview.platform(row.context)}</td>
              <td class="max-w-[10rem] truncate">{row.context.discord_user}</td>
              <td class="max-w-md">
                <button
                  id={"show-#{row.id}"}
                  type="button"
                  phx-click="show"
                  phx-value-id={row.id}
                  class="block w-full truncate text-left link link-hover"
                >
                  {row.context.question}
                </button>
              </td>
              <td>
                <div class="flex flex-wrap gap-1">
                  <.flag_badge :for={flag <- row.flags} flag={flag} label={@flag_labels[flag]} />
                </div>
              </td>
              <td>{format_seconds(row.context.elapsed_time)}</td>
              <td>
                <.trace_link trace_id={row.context.langfuse_trace_id} />
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.details_modal :if={@selected} selected={@selected} flag_labels={@flag_labels} />
    </div>
    """
  end

  attr :flag, :string, required: true
  attr :label, :string, required: true

  defp flag_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm whitespace-nowrap", flag_class(@flag)]}>{@label}</span>
    """
  end

  attr :trace_id, :string, default: nil

  defp trace_link(assigns) do
    ~H"""
    <a
      :if={@trace_id}
      href={langfuse_trace_url(@trace_id)}
      target="_blank"
      rel="noopener"
      class="link link-primary"
    >
      Langfuse
    </a>
    <span :if={!@trace_id} class="text-base-content/40">-</span>
    """
  end

  attr :selected, :map, required: true
  attr :flag_labels, :map, required: true

  defp details_modal(assigns) do
    ~H"""
    <div id="review-details" class="modal modal-open" phx-window-keydown="close" phx-key="escape">
      <div class="modal-box max-w-4xl">
        <div class="flex items-start justify-between gap-4 mb-4">
          <div>
            <h3 class="font-bold text-lg">Turn #{@selected.context.id}</h3>
            <p class="text-sm text-base-content/60">
              {AiContextReview.platform(@selected.context)} · {@selected.context.discord_user} · {@selected.context.guild_name} · {Calendar.strftime(
                @selected.context.inserted_at,
                "%Y-%m-%d %H:%M:%S"
              )} UTC
            </p>
          </div>
          <button id="close-details" type="button" class="btn btn-sm btn-ghost" phx-click="close">
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <div class="flex flex-wrap gap-1 mb-4">
          <.flag_badge :for={flag <- @selected.flags} flag={flag} label={@flag_labels[flag]} />
        </div>

        <dl class="grid grid-cols-[10rem_1fr] gap-x-4 gap-y-2 text-sm mb-4">
          <dt class="text-base-content/60">Status</dt>
          <dd>{@selected.context.status}</dd>
          <dt class="text-base-content/60">Delivery</dt>
          <dd>{@selected.context.delivery_status || "-"}</dd>
          <dt :if={@selected.context.delivery_error} class="text-base-content/60">Delivery error</dt>
          <dd :if={@selected.context.delivery_error} class="break-all font-mono text-xs">
            {String.slice(@selected.context.delivery_error, 0, 500)}
          </dd>
          <dt :if={@selected.context.error_message} class="text-base-content/60">Error</dt>
          <dd :if={@selected.context.error_message} class="break-all">
            {@selected.context.error_message}
          </dd>
          <dt class="text-base-content/60">Tools used</dt>
          <dd>{Enum.join(@selected.context.tools_used || [], ", ")}</dd>
          <dt class="text-base-content/60">Tool issues</dt>
          <dd>{Enum.join(@selected.context.tool_issues || [], ", ")}</dd>
          <dt class="text-base-content/60">Seconds / cost</dt>
          <dd>
            {format_seconds(@selected.context.elapsed_time)} s · ${@selected.context.total_cost}
          </dd>
          <dt class="text-base-content/60">Trace</dt>
          <dd><.trace_link trace_id={@selected.context.langfuse_trace_id} /></dd>
        </dl>

        <h4 class="font-semibold mb-1">Question</h4>
        <p class="whitespace-pre-wrap bg-base-200 rounded-box p-3 mb-4 text-sm">
          {@selected.context.question}
        </p>

        <h4 class="font-semibold mb-1">Answer</h4>
        <p class="whitespace-pre-wrap bg-base-200 rounded-box p-3 text-sm max-h-[50vh] overflow-y-auto">
          {@selected.context.answer || "-"}
        </p>
      </div>
      <div class="modal-backdrop" phx-click="close"></div>
    </div>
    """
  end

  defp flag_class(flag) when flag in ["delivery_failed", "error"], do: "badge-error"

  defp flag_class(flag) when flag in ["degraded", "tool_issue", "language_mismatch"],
    do: "badge-warning"

  defp flag_class(_flag), do: "badge-info"

  defp format_seconds(seconds) when is_number(seconds),
    do: :erlang.float_to_binary(seconds / 1, decimals: 1)

  defp format_seconds(_seconds), do: "-"

  defp langfuse_trace_url(trace_id) do
    System.get_env("AI_SERVER_LANGFUSE_TRACES_URL", @default_langfuse_traces_url) <> trace_id
  end
end

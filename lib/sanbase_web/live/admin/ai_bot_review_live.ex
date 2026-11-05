defmodule SanbaseWeb.Admin.AiBotReviewLive do
  @moduledoc """
  Daily review of AI bot turns (Discord and Telegram). Lists the turns that
  were flagged (failed delivery, errors, empty tools, wrong language, down
  votes, slow) and exports them as JSONL for deeper analysis.

  The issues panel groups those problems by signature
  (`Sanbase.DiscordBot.AiReviewIssues`). Admin Panel Editors and Owners can
  resolve and reopen them here, as with the `/admin_api/ai_review` API.
  """

  use SanbaseWeb, :live_view

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.AiContextReview
  alias Sanbase.DiscordBot.AiReviewIssues

  @page_size 100

  @flag_labels AiContextReview.flag_labels()

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI Bot Review")
     |> assign(:selected, nil)
     |> assign(:can_resolve?, AiReviewIssues.can_resolve?(socket.assigns.current_user_role_ids))
     |> assign(:include_resolved, false)
     |> stream(:rows, [])
     |> load_issues()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = AiContextReview.parse_filters(params)
    # Counts cover the whole range; only the current page is rendered.
    all_rows = AiContextReview.list_for_filters(filters)
    rows = AiContextReview.select(all_rows, filters)
    page_count = max(div(length(rows) + @page_size - 1, @page_size), 1)
    page = params |> parse_page() |> min(page_count)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filter_params(filters), as: :filters))
     |> assign(:total_count, length(all_rows))
     |> assign(:shown_count, length(rows))
     |> assign(:page, page)
     |> assign(:page_count, page_count)
     |> assign(:flag_counts, AiContextReview.flag_counts(all_rows))
     |> assign(:params, params)
     |> stream(:rows, with_issues(Enum.slice(rows, (page - 1) * @page_size, @page_size)),
       reset: true
     )}
  end

  # Each row carries the issues its turn belongs to, for the status column.
  defp with_issues(rows) do
    issues = AiReviewIssues.issues_by_turn(Enum.map(rows, & &1.id))
    Enum.map(rows, &Map.put(&1, :issues, Map.get(issues, &1.id, [])))
  end

  defp load_issues(socket) do
    issues = AiReviewIssues.list_for_review(include_resolved: socket.assigns.include_resolved)

    socket
    |> assign(:issues_count, length(issues))
    |> stream(:issues, issues, reset: true)
  end

  defp parse_page(params) do
    case Integer.parse(params["page"] || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
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
    {:noreply, assign(socket, :selected, selected_turn(String.to_integer(id)))}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  def handle_event("toggle_resolved", _params, socket) do
    {:noreply,
     socket
     |> assign(:include_resolved, not socket.assigns.include_resolved)
     |> load_issues()}
  end

  def handle_event("resolve_issue", %{"resolve" => %{"id" => id} = params}, socket) do
    note = params["note"] |> to_string() |> String.trim()
    note = if note == "", do: nil, else: String.slice(note, 0, 5000)

    change_issue(socket, id, &AiReviewIssues.resolve(&1, socket.assigns.current_user, note))
  end

  def handle_event("reopen_issue", %{"id" => id}, socket) do
    change_issue(socket, id, &AiReviewIssues.reopen/1)
  end

  # The buttons are shown only to Editors and Owners; the check is repeated
  # here because events can be sent without them.
  defp change_issue(socket, id, fun) do
    with true <- socket.assigns.can_resolve?,
         {:ok, issue} <- AiReviewIssues.get(String.to_integer(id)),
         {:ok, _issue} <- fun.(issue) do
      {:noreply, refresh(socket)}
    else
      false ->
        {:noreply, put_flash(socket, :error, "An Admin Panel Editor or Owner role is required")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update the issue")}
    end
  end

  # Re-reads the issues panel, the statuses of the turns on the page, and the
  # open turn details.
  defp refresh(socket) do
    {:noreply, socket} = handle_params(socket.assigns.params, nil, socket)

    selected =
      case socket.assigns.selected do
        %{context: %{id: id}} -> selected_turn(id)
        nil -> nil
      end

    socket
    |> load_issues()
    |> assign(:selected, selected)
  end

  defp selected_turn(id) do
    case AiContext.by_id(id) do
      nil ->
        nil

      context ->
        %{
          context: context,
          flags: AiContextReview.flags_for(context),
          issues: Map.get(AiReviewIssues.issues_by_turn([id]), id, [])
        }
    end
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

      <section id="issues-panel" class="mb-8">
        <div class="flex flex-wrap items-center justify-between gap-2 mb-2">
          <h2 class="text-lg font-semibold">
            Issues
            <span class="text-sm font-normal text-base-content/60">
              {@issues_count} {if @include_resolved, do: "in total", else: "open or recurred"}
            </span>
          </h2>
          <button
            id="toggle-resolved"
            type="button"
            phx-click="toggle_resolved"
            class="btn btn-xs btn-ghost"
          >
            {if @include_resolved, do: "Hide resolved", else: "Show resolved"}
          </button>
        </div>
        <div class="rounded-box border border-base-300 overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Status</th>
                <th>Issue</th>
                <th>Turns</th>
                <th>Last seen (UTC)</th>
                <th>Latest</th>
                <th>Resolution</th>
                <th :if={@can_resolve?}></th>
              </tr>
            </thead>
            <tbody id="issues" phx-update="stream">
              <tr id="issues-empty" class="hidden only:table-row">
                <td colspan="7" class="text-center text-base-content/60 py-6">
                  No open issues.
                </td>
              </tr>
              <tr :for={{dom_id, issue} <- @streams.issues} id={dom_id}>
                <td><.status_badge status={issue.status} /></td>
                <td class="font-mono text-xs max-w-sm break-all">{issue.signature}</td>
                <td>
                  {issue.occurrences}
                  <span :if={issue.recurrences > 0} class="text-base-content/60">
                    · recurred {issue.recurrences}×
                  </span>
                </td>
                <td class="whitespace-nowrap">
                  {Calendar.strftime(issue.last_seen_at, "%Y-%m-%d %H:%M")}
                </td>
                <td class="whitespace-nowrap">
                  <button
                    :if={issue.last_ai_context_id}
                    id={"issue-turn-#{issue.id}"}
                    type="button"
                    phx-click="show"
                    phx-value-id={issue.last_ai_context_id}
                    class="link link-hover"
                  >
                    Turn #{issue.last_ai_context_id}
                  </button>
                  <span :if={issue.last_ai_context} class="ml-1">
                    <.trace_link trace_id={issue.last_ai_context.langfuse_trace_id} />
                  </span>
                </td>
                <td class="text-xs max-w-xs">
                  <span :if={issue.resolved_at}>
                    {Calendar.strftime(issue.resolved_at, "%Y-%m-%d")}
                    <span :if={issue.resolved_by}>by {issue.resolved_by.username}</span>
                  </span>
                  <p :if={issue.resolution_note} class="text-base-content/70 break-words">
                    {issue.resolution_note}
                  </p>
                </td>
                <td :if={@can_resolve?}><.issue_actions issue={issue} /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

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
              <th>Issue status</th>
              <th>Seconds</th>
              <th>Trace</th>
            </tr>
          </thead>
          <tbody id="review-rows" phx-update="stream">
            <tr id="review-rows-empty" class="hidden only:table-row">
              <td colspan="8" class="text-center text-base-content/60 py-8">
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
              <td>
                <div class="flex flex-wrap gap-1">
                  <.status_badge
                    :for={status <- row.issues |> Enum.map(& &1.status) |> Enum.uniq()}
                    status={status}
                  />
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

      <div
        :if={@page_count > 1}
        id="review-pages"
        class="flex items-center justify-end gap-2 mt-4 text-sm"
      >
        <.link
          :if={@page > 1}
          id="prev-page"
          patch={~p"/admin/ai_bot_review?#{Map.put(@export_params, "page", @page - 1)}"}
          class="btn btn-sm btn-ghost"
        >
          <.icon name="hero-chevron-left" class="w-4 h-4" /> Newer
        </.link>
        <span class="text-base-content/60">Page {@page} of {@page_count}</span>
        <.link
          :if={@page < @page_count}
          id="next-page"
          patch={~p"/admin/ai_bot_review?#{Map.put(@export_params, "page", @page + 1)}"}
          class="btn btn-sm btn-ghost"
        >
          Older <.icon name="hero-chevron-right" class="w-4 h-4" />
        </.link>
      </div>

      <.details_modal
        :if={@selected}
        selected={@selected}
        flag_labels={@flag_labels}
        can_resolve?={@can_resolve?}
      />
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

  attr :status, :string, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm whitespace-nowrap", status_class(@status)]}>
      {String.capitalize(@status)}
    </span>
    """
  end

  attr :issue, :map, required: true

  # Resolve with an optional note (e.g. the PR link), or reopen.
  defp issue_actions(assigns) do
    ~H"""
    <.form
      :if={@issue.status != "resolved"}
      for={to_form(%{"id" => @issue.id, "note" => ""}, as: :resolve)}
      id={"resolve-form-#{@issue.id}"}
      phx-submit="resolve_issue"
      class="flex items-center gap-1"
    >
      <input type="hidden" name="resolve[id]" value={@issue.id} />
      <input
        type="text"
        name="resolve[note]"
        placeholder="Note or PR link"
        class="input input-xs input-bordered w-40"
      />
      <button id={"resolve-#{@issue.id}"} type="submit" class="btn btn-xs btn-success">
        Resolve
      </button>
    </.form>
    <button
      :if={@issue.status == "resolved"}
      id={"reopen-#{@issue.id}"}
      type="button"
      phx-click="reopen_issue"
      phx-value-id={@issue.id}
      class="btn btn-xs btn-ghost"
    >
      Reopen
    </button>
    """
  end

  attr :trace_id, :string, default: nil

  defp trace_link(assigns) do
    ~H"""
    <a
      :if={@trace_id}
      href={AiContextReview.langfuse_trace_url(@trace_id)}
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
  attr :can_resolve?, :boolean, default: false

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

        <div :if={@selected.issues != []} id="turn-issues" class="mb-4">
          <h4 class="font-semibold mb-1">Issues</h4>
          <ul class="flex flex-col gap-2">
            <li
              :for={issue <- @selected.issues}
              id={"turn-issue-#{issue.id}"}
              class="flex flex-wrap items-center gap-2 text-sm"
            >
              <.status_badge status={issue.status} />
              <span class="font-mono text-xs break-all">{issue.signature}</span>
              <span class="text-base-content/60">{issue.occurrences} turns</span>
              <span :if={@can_resolve?} class="ml-auto"><.issue_actions issue={issue} /></span>
            </li>
          </ul>
        </div>

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

  defp status_class("recurred"), do: "badge-error"
  defp status_class("open"), do: "badge-warning"
  defp status_class(_status), do: "badge-success"

  defp format_seconds(seconds) when is_number(seconds),
    do: :erlang.float_to_binary(seconds / 1, decimals: 1)

  defp format_seconds(_seconds), do: "-"
end

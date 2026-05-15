defmodule SanbaseWeb.Admin.McpToolInvocationsLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Accounts.User
  alias Sanbase.MCP.ToolInvocation
  alias SanbaseWeb.AdminSharedComponents

  @page_size 50
  @rate_limited_window_seconds 7 * 24 * 3600

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "MCP Tool Invocations")
      |> assign(:tab, :invocations)
      |> assign(:tool_name_filter, "")
      |> assign(:email_search, "")
      |> assign(:metric_search, "")
      |> assign(:plan_filter, "")
      |> assign(:include_team, false)
      |> assign(:hide_auto_rejected, true)
      |> assign(:expanded_sessions, MapSet.new())
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:tool_names, ToolInvocation.tool_names())
      |> assign(:plan_names, ToolInvocation.plan_names())
      |> assign(:modal_invocation, nil)
      |> assign(:timeline_window, "7d")
      |> assign(:ban_target, nil)
      |> assign(:rate_limited_users_count, rate_limited_users_count())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tab = parse_tab(params["tab"])

    socket =
      if socket.assigns[:tab] == tab and tab_loaded?(socket, tab) do
        socket
      else
        socket |> assign(:tab, tab) |> load_tab(tab)
      end

    {:noreply, socket}
  end

  defp parse_tab("timeline"), do: :timeline
  defp parse_tab("rate_limited"), do: :rate_limited
  defp parse_tab(_), do: :invocations

  # Was the data for the requested tab already loaded? Avoids re-running
  # the tab's queries when handle_params fires for an unrelated URL update.
  defp tab_loaded?(socket, :invocations), do: Map.has_key?(socket.assigns, :stats)
  defp tab_loaded?(socket, :timeline), do: Map.has_key?(socket.assigns, :timeline_rows)
  defp tab_loaded?(socket, :rate_limited), do: Map.has_key?(socket.assigns, :rate_limited_rows)

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/mcp_tool_invocations?tab=#{tab}")}
  end

  def handle_event("filter_tool_name", %{"tool_name" => tool_name}, socket) do
    {:noreply,
     socket
     |> assign(:tool_name_filter, tool_name)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("search_email", %{"email_search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:email_search, search)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("filter_metric", %{"metric_search" => metric}, socket) do
    {:noreply,
     socket
     |> assign(:metric_search, metric)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("filter_plan", %{"plan_name" => plan}, socket) do
    {:noreply,
     socket
     |> assign(:plan_filter, plan)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("toggle_include_team", _params, socket) do
    {:noreply,
     socket
     |> assign(:include_team, not socket.assigns.include_team)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("toggle_hide_auto_rejected", _params, socket) do
    {:noreply,
     socket
     |> assign(:hide_auto_rejected, not socket.assigns.hide_auto_rejected)
     |> assign(:page, 1)
     |> load_invocations()}
  end

  def handle_event("toggle_session", %{"session-id" => sid}, socket) do
    expanded = socket.assigns.expanded_sessions

    expanded =
      if MapSet.member?(expanded, sid),
        do: MapSet.delete(expanded, sid),
        else: MapSet.put(expanded, sid)

    {:noreply, assign(socket, :expanded_sessions, expanded)}
  end

  def handle_event("next_page", _, socket) do
    page = min(socket.assigns.page + 1, socket.assigns.total_pages)
    {:noreply, socket |> assign(:page, page) |> load_invocations()}
  end

  def handle_event("prev_page", _, socket) do
    page = max(1, socket.assigns.page - 1)
    {:noreply, socket |> assign(:page, page) |> load_invocations()}
  end

  def handle_event("show_params", %{"id" => id}, socket) do
    id = String.to_integer(id)
    invocation = Enum.find(socket.assigns.invocations, &(&1.id == id))
    {:noreply, assign(socket, :modal_invocation, invocation)}
  end

  def handle_event("close_params", _, socket) do
    {:noreply, assign(socket, :modal_invocation, nil)}
  end

  def handle_event("set_timeline_window", %{"window" => window}, socket) do
    {:noreply, socket |> assign(:timeline_window, window) |> load_timeline()}
  end

  def handle_event("open_ban", %{"user-id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    target = Enum.find(socket.assigns.rate_limited_rows, &(&1.user_id == user_id))
    {:noreply, assign(socket, :ban_target, target)}
  end

  def handle_event("close_ban", _, socket) do
    {:noreply, assign(socket, :ban_target, nil)}
  end

  def handle_event("confirm_ban", params, socket) do
    case socket.assigns.ban_target do
      nil ->
        {:noreply, socket}

      %{user_id: user_id} ->
        reason = params |> Map.get("reason", "") |> String.trim()
        reason = if reason == "", do: "Banned via admin", else: reason

        with {:ok, user} <- User.by_id(user_id) do
          User.mcp_ban!(user, reason)
        end

        {:noreply, socket |> assign(:ban_target, nil) |> load_rate_limited()}
    end
  end

  def handle_event("unban", %{"user-id" => user_id}, socket) do
    user_id = String.to_integer(user_id)

    with {:ok, user} <- User.by_id(user_id) do
      User.mcp_unban!(user)
    end

    {:noreply, load_rate_limited(socket)}
  end

  defp load_tab(socket, :invocations), do: assign_invocations_tab(socket)
  defp load_tab(socket, :timeline), do: load_timeline(socket)
  defp load_tab(socket, :rate_limited), do: load_rate_limited(socket)

  defp assign_invocations_tab(socket) do
    since = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
    stats = ToolInvocation.stats_since(since)
    noise = ToolInvocation.noise_counts_since(since)

    socket
    |> assign(:stats, stats)
    |> assign(:noise, noise)
    |> load_invocations()
  end

  defp load_invocations(socket) do
    opts = filter_opts(socket.assigns)
    invocations = ToolInvocation.list_invocations(opts)
    total = ToolInvocation.count_invocations(opts)
    total_pages = max(1, ceil(total / socket.assigns.page_size))

    socket
    |> assign(:invocations, invocations)
    |> assign(:grouped_rows, group_by_session(invocations))
    |> assign(:total_count, total)
    |> assign(:total_pages, total_pages)
  end

  # Tags each invocation with its role in the grouped view:
  #   * :single — no session, or the only call in its session on this page
  #   * :header — first row of a session that has >1 calls on this page
  #   * :child  — subsequent row of such a session (hidden when collapsed)
  #
  # Rows from the same session are clustered together (header first, then
  # children) so that when a user has multiple concurrent MCP sessions, the
  # timestamp-interleaved rows are re-grouped visually. Cluster order follows
  # each session's newest row, preserving the overall desc-by-timestamp feel.
  defp group_by_session(invocations) do
    {ordered_keys, by_key} =
      Enum.reduce(invocations, {[], %{}}, fn inv, {order, acc} ->
        key = session_key(inv)

        case Map.get(acc, key) do
          nil -> {[key | order], Map.put(acc, key, [inv])}
          rows -> {order, Map.put(acc, key, [inv | rows])}
        end
      end)

    ordered_keys
    |> Enum.reverse()
    |> Enum.flat_map(fn key -> by_key |> Map.fetch!(key) |> Enum.reverse() |> build_group() end)
  end

  defp session_key(%{session_id: sid} = inv) when sid in [nil, ""], do: {:none, inv.id}
  defp session_key(%{session_id: sid}), do: {:sid, sid}

  defp build_group([inv]),
    do: [%{inv: inv, role: :single, session_id: inv.session_id, count: 1}]

  defp build_group([head | tail]) do
    count = 1 + length(tail)
    sid = head.session_id

    [
      %{inv: head, role: :header, session_id: sid, count: count}
      | Enum.map(tail, &%{inv: &1, role: :child, session_id: sid, count: count})
    ]
  end

  defp load_timeline(socket) do
    {since, bucket} = window_to_since_and_bucket(socket.assigns.timeline_window)

    socket
    |> assign(:timeline_rows, ToolInvocation.time_series(since: since, bucket: bucket))
    |> assign(:top_clients, ToolInvocation.top_by(:client, since))
    |> assign(:top_tools, ToolInvocation.top_by(:tool_name, since))
    |> assign(:top_plans, ToolInvocation.top_by(:plan_name, since))
    |> assign(:timeline_bucket, bucket)
    |> assign(:timeline_noise, ToolInvocation.noise_counts_since(since))
  end

  defp load_rate_limited(socket) do
    since = DateTime.add(DateTime.utc_now(), -@rate_limited_window_seconds, :second)

    socket
    |> assign(:rate_limited_rows, ToolInvocation.rate_limited_users(since: since))
    |> assign(:rate_limited_users_count, ToolInvocation.rate_limited_users_count(since))
  end

  defp rate_limited_users_count do
    since = DateTime.add(DateTime.utc_now(), -@rate_limited_window_seconds, :second)
    ToolInvocation.rate_limited_users_count(since)
  end

  defp window_to_since_and_bucket("24h"), do: {hours_ago(24), "hour"}
  defp window_to_since_and_bucket("7d"), do: {hours_ago(7 * 24), "day"}
  defp window_to_since_and_bucket("30d"), do: {hours_ago(30 * 24), "day"}
  defp window_to_since_and_bucket(_), do: {hours_ago(7 * 24), "day"}

  defp hours_ago(hours), do: DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

  defp filter_opts(assigns) do
    [
      tool_name: assigns.tool_name_filter,
      email_search: assigns.email_search,
      metric: assigns.metric_search,
      plan_name: assigns.plan_filter,
      exclude_team_members: not assigns.include_team,
      hide_auto_rejected: assigns.hide_auto_rejected,
      page: assigns.page,
      page_size: assigns.page_size
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col w-full px-4 py-6">
      <h1 class="text-2xl font-bold mb-6">{@page_title}</h1>

      <.tab_bar tab={@tab} rate_limited_users_count={@rate_limited_users_count} />

      <.invocations_panel :if={@tab == :invocations} {assigns} />
      <.timeline_panel :if={@tab == :timeline} {assigns} />
      <.rate_limited_panel :if={@tab == :rate_limited} {assigns} />

      <.params_modal modal_invocation={@modal_invocation} />
      <.ban_modal ban_target={@ban_target} />
    </div>
    """
  end

  defp tab_bar(assigns) do
    ~H"""
    <div role="tablist" class="tabs tabs-boxed mb-4 w-fit">
      <a
        role="tab"
        phx-click="switch_tab"
        phx-value-tab="invocations"
        class={["tab", @tab == :invocations && "tab-active"]}
      >
        Invocations
      </a>
      <a
        role="tab"
        phx-click="switch_tab"
        phx-value-tab="timeline"
        class={["tab", @tab == :timeline && "tab-active"]}
      >
        Timeline
      </a>
      <a
        role="tab"
        phx-click="switch_tab"
        phx-value-tab="rate_limited"
        class={["tab", @tab == :rate_limited && "tab-active"]}
      >
        Rate-limited users
        <span
          :if={@rate_limited_users_count > 0}
          class="badge badge-error badge-sm ml-1"
        >
          {@rate_limited_users_count}
        </span>
      </a>
    </div>
    """
  end

  defp invocations_panel(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-4 gap-4 mb-6">
      <div class="lg:col-span-3">
        <.stats_bar stats={@stats} />
      </div>
      <.noise_panel noise={@noise} window_label="24h" />
    </div>

    <div class="flex flex-col sm:flex-row gap-4 mb-6">
      <fieldset class="fieldset">
        <legend class="fieldset-legend">Tool Name</legend>
        <select
          id="tool-name-filter"
          phx-change="filter_tool_name"
          name="tool_name"
          class="select select-sm"
        >
          <option value="">All Tools</option>
          <option :for={tn <- @tool_names} value={tn} selected={tn == @tool_name_filter}>
            {tn}
          </option>
        </select>
      </fieldset>

      <fieldset class="fieldset">
        <legend class="fieldset-legend">Search User Email</legend>
        <form phx-change="search_email" phx-submit="search_email" id="email-search-form">
          <input
            type="text"
            name="email_search"
            id="email-search-input"
            value={@email_search}
            placeholder="Search by email..."
            phx-debounce="300"
            class="input input-sm w-72"
          />
        </form>
      </fieldset>

      <fieldset class="fieldset">
        <legend class="fieldset-legend">Search Metric</legend>
        <form phx-change="filter_metric" phx-submit="filter_metric" id="metric-search-form">
          <input
            type="text"
            name="metric_search"
            id="metric-search-input"
            value={@metric_search}
            placeholder="Filter by metric..."
            phx-debounce="300"
            class="input input-sm w-72"
          />
        </form>
      </fieldset>

      <fieldset class="fieldset">
        <legend class="fieldset-legend">Plan</legend>
        <select id="plan-filter" phx-change="filter_plan" name="plan_name" class="select select-sm">
          <option value="">All Plans</option>
          <option :for={pn <- @plan_names} value={pn} selected={pn == @plan_filter}>
            {pn}
          </option>
        </select>
      </fieldset>

      <fieldset class="fieldset">
        <legend class="fieldset-legend">Team members</legend>
        <label class="label cursor-pointer gap-2">
          <input
            type="checkbox"
            class="toggle toggle-sm"
            checked={@include_team}
            phx-click="toggle_include_team"
          />
          <span class="label-text text-sm">Include team</span>
        </label>
      </fieldset>

      <fieldset class="fieldset">
        <legend class="fieldset-legend">Auto-rejected</legend>
        <label class="label cursor-pointer gap-2">
          <input
            type="checkbox"
            class="toggle toggle-sm"
            checked={@hide_auto_rejected}
            phx-click="toggle_hide_auto_rejected"
          />
          <span class="label-text text-sm">Hide rate-limit + banned</span>
        </label>
      </fieldset>

      <div class="flex items-end">
        <span class="text-sm text-base-content/60">
          {if @total_count > 0,
            do: "#{@total_count} invocations found",
            else: "No invocations found"}
        </span>
      </div>
    </div>

    <div class="rounded-box border border-base-300 overflow-x-auto">
      <table class="table table-zebra table-sm">
        <thead>
          <tr>
            <th></th>
            <th>Timestamp</th>
            <th>User</th>
            <th>Tool Name</th>
            <th>Kind</th>
            <th>Client</th>
            <th>Plan</th>
            <th>Metrics</th>
            <th>Slugs</th>
            <th>Duration (ms)</th>
            <th>Response Size</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <AdminSharedComponents.empty_table_row
            :if={@invocations == []}
            colspan={12}
            message="No invocations found matching your filters."
          />
          <tr
            :for={row <- @grouped_rows}
            :if={row.role != :child or MapSet.member?(@expanded_sessions, row.session_id)}
            id={"inv-#{row.inv.id}"}
            class={[
              row.role == :child && "bg-base-200/40 border-l-4 border-primary/60"
            ]}
          >
            <td class="whitespace-nowrap">
              <button
                :if={row.role == :header}
                type="button"
                phx-click="toggle_session"
                phx-value-session-id={row.session_id}
                class="btn btn-xs btn-ghost mr-1"
                title={"Session " <> short_session(row.session_id) <> " — " <> Integer.to_string(row.count) <> " calls"}
              >
                {if MapSet.member?(@expanded_sessions, row.session_id), do: "▼", else: "▶"}
                <span class="badge badge-xs badge-neutral ml-1">{row.count}</span>
              </button>
              <span
                :if={row.role == :child}
                class="btn btn-xs btn-ghost mr-1"
                style="visibility: hidden"
                aria-hidden="true"
              >
                ▶ <span class="badge badge-xs badge-neutral ml-1">{row.count}</span>
              </span>
              <button
                type="button"
                phx-click="show_params"
                phx-value-id={row.inv.id}
                class="btn btn-xs btn-primary"
              >
                Show
              </button>
            </td>
            <td class="text-base-content/70">{format_datetime(row.inv.inserted_at)}</td>
            <td class="font-mono">
              <.user_label user={row.inv.user} />
            </td>
            <td><.tool_badge tool_name={row.inv.tool_name} /></td>
            <td class="text-base-content/70">{row.inv.kind}</td>
            <td class="text-base-content/70">{row.inv.client || "-"}</td>
            <td class="text-base-content/70 whitespace-nowrap">
              <.plan_badge plan_name={row.inv.plan_name} product_code={row.inv.product_code} />
            </td>
            <td class="text-base-content/70">{Enum.join(row.inv.metrics, ", ")}</td>
            <td class="text-base-content/70">{Enum.join(row.inv.slugs, ", ")}</td>
            <td class="text-base-content/70">{row.inv.duration_ms}</td>
            <td class="text-base-content/70">{format_bytes(row.inv.response_size_bytes)}</td>
            <td><.status_badge is_successful={row.inv.is_successful} /></td>
          </tr>
        </tbody>
      </table>
    </div>

    <.pagination page={@page} total_pages={@total_pages} total_count={@total_count} />
    """
  end

  defp timeline_panel(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <div role="tablist" class="tabs tabs-boxed w-fit">
        <a
          :for={w <- ["24h", "7d", "30d"]}
          role="tab"
          phx-click="set_timeline_window"
          phx-value-window={w}
          class={["tab", @timeline_window == w && "tab-active"]}
        >
          {w}
        </a>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div class="rounded-box border border-base-300 overflow-hidden lg:col-span-2">
          <div class="px-3 py-2 bg-base-200 text-sm font-semibold">
            Usage per {@timeline_bucket}
          </div>
          <table class="table table-zebra table-sm">
            <thead>
              <tr>
                <th>Bucket ({@timeline_bucket})</th>
                <th class="text-right">Total invocations</th>
                <th class="text-right">Unique users</th>
              </tr>
            </thead>
            <tbody>
              <AdminSharedComponents.empty_table_row
                :if={@timeline_rows == []}
                colspan={3}
                message="No invocations in this window."
              />
              <tr :for={{bucket, total, uniq} <- @timeline_rows}>
                <td class="text-base-content/70">{format_bucket(bucket, @timeline_bucket)}</td>
                <td class="text-right font-mono">{total}</td>
                <td class="text-right font-mono">{uniq}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="flex flex-col gap-4">
          <.top_table title="Top clients" rows={@top_clients} />
          <.top_table title="Top tools / prompts" rows={@top_tools} />
          <.top_table title="Top plans" rows={@top_plans} />
          <.noise_panel noise={@timeline_noise} window_label={@timeline_window} />
        </div>
      </div>
    </div>
    """
  end

  defp top_table(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 overflow-hidden">
      <div class="px-3 py-2 bg-base-200 text-sm font-semibold">{@title}</div>
      <table class="table table-zebra table-sm">
        <tbody>
          <AdminSharedComponents.empty_table_row
            :if={@rows == []}
            colspan={2}
            message="No data."
          />
          <tr :for={{label, count} <- @rows}>
            <td class="text-base-content/70">{label || "-"}</td>
            <td class="text-right font-mono">{count}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp rate_limited_panel(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <div class="text-sm text-base-content/60">
        Users with rate-limit rejections in the last 7 days. Ban from MCP blocks just the MCP server; the rest of Sanbase is unaffected.
      </div>
      <div class="rounded-box border border-base-300 overflow-hidden">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>User</th>
              <th class="text-right">Rate-limit hits</th>
              <th>Last hit</th>
              <th>MCP-banned?</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <AdminSharedComponents.empty_table_row
              :if={@rate_limited_rows == []}
              colspan={5}
              message="No rate-limited users in this window."
            />
            <tr :for={row <- @rate_limited_rows}>
              <td class="font-mono">
                <.user_label user={row} />
              </td>
              <td class="text-right font-mono">{row.hits}</td>
              <td class="text-base-content/70">{format_datetime(row.last_hit)}</td>
              <td>
                <span :if={row.is_mcp_banned} class="badge badge-sm badge-error">Banned</span>
                <span :if={!row.is_mcp_banned} class="badge badge-sm badge-ghost">Active</span>
              </td>
              <td>
                <button
                  :if={!row.is_mcp_banned}
                  phx-click="open_ban"
                  phx-value-user-id={row.user_id}
                  class="btn btn-xs btn-error"
                >
                  Ban from MCP
                </button>
                <button
                  :if={row.is_mcp_banned}
                  phx-click="unban"
                  phx-value-user-id={row.user_id}
                  class="btn btn-xs btn-ghost"
                >
                  Unban
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp params_modal(assigns) do
    ~H"""
    <.modal
      :if={@modal_invocation}
      id="mcp-invocation-modal"
      show
      on_cancel={JS.push("close_params")}
      max_modal_width="max-w-4xl"
    >
      <div class="text-sm text-base-content/60 mb-2">
        Invocation #{@modal_invocation.id} — {@modal_invocation.tool_name}
        <span class="badge badge-xs ml-1">{@modal_invocation.kind}</span>
        <span :if={@modal_invocation.client} class="badge badge-xs ml-1">
          {@modal_invocation.client}
        </span>
      </div>
      <div class="mockup-code bg-neutral text-neutral-content rounded-box p-4 text-xs overflow-x-auto">
        <div class="mb-2 text-neutral-content/60">Params</div>
        <pre>{Jason.encode!(@modal_invocation.params || %{}, pretty: true)}</pre>
        <div :if={@modal_invocation.error_message} class="mt-3 text-error">
          <div class="mb-1 text-neutral-content/60">Error message</div>
          <pre>{@modal_invocation.error_message}</pre>
        </div>
        <div :if={@modal_invocation.user_agent} class="mt-3">
          <div class="mb-1 text-neutral-content/60">User-Agent</div>
          <pre class="whitespace-pre-wrap break-all">{@modal_invocation.user_agent}</pre>
        </div>
        <div :if={@modal_invocation.session_id} class="mt-3">
          <div class="mb-1 text-neutral-content/60">Session ID</div>
          <pre>{@modal_invocation.session_id}</pre>
        </div>
      </div>
    </.modal>
    """
  end

  defp ban_modal(assigns) do
    {_id, target_label} = user_id_and_label(assigns[:ban_target])
    assigns = assign(assigns, target_label: target_label)

    ~H"""
    <.modal
      :if={@ban_target}
      id="mcp-ban-modal"
      show
      on_cancel={JS.push("close_ban")}
      max_modal_width="max-w-md"
    >
      <h3 class="font-semibold mb-2">
        Ban {@target_label} from MCP
      </h3>
      <p class="text-sm text-base-content/60 mb-4">
        The user keeps full access to the rest of Sanbase. They will see a banned message on the next MCP call.
      </p>
      <form phx-submit="confirm_ban">
        <fieldset class="fieldset">
          <legend class="fieldset-legend">Reason (optional)</legend>
          <textarea
            name="reason"
            class="textarea textarea-sm w-full"
            rows="3"
            placeholder="e.g. abusive automated traffic"
          ></textarea>
        </fieldset>
        <div class="flex justify-end gap-2 mt-4">
          <button type="button" phx-click="close_ban" class="btn btn-sm btn-ghost">Cancel</button>
          <button type="submit" class="btn btn-sm btn-error">Confirm ban</button>
        </div>
      </form>
    </.modal>
    """
  end

  defp stats_bar(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
      <AdminSharedComponents.mini_stat_card
        :for={{tool_name, count} <- Enum.sort_by(@stats, fn {_, c} -> -c end)}
        label={tool_name}
        count={count}
        suffix="(24h)"
        truncate
      />
    </div>
    """
  end

  defp noise_panel(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-200/50 p-3 text-sm">
      <div class="font-semibold text-base-content/70 mb-2">
        Filtered out ({@window_label})
      </div>
      <dl class="grid grid-cols-2 gap-x-3 gap-y-1">
        <dt class="text-base-content/60">Team</dt>
        <dd class="text-right font-mono">{@noise.team}</dd>
        <dt class="text-base-content/60">Rate-limited</dt>
        <dd class="text-right font-mono">{@noise.rate_limited}</dd>
        <dt class="text-base-content/60">Banned attempts</dt>
        <dd class="text-right font-mono">{@noise.banned}</dd>
      </dl>
    </div>
    """
  end

  defp tool_badge(assigns) do
    ~H"""
    <span class="badge badge-sm badge-secondary">{@tool_name}</span>
    """
  end

  defp plan_badge(assigns) do
    ~H"""
    <span :if={@plan_name} class={["badge badge-sm", plan_badge_class(@plan_name)]}>
      {@plan_name}
    </span>
    <span :if={@plan_name && @product_code} class="badge badge-xs badge-ghost ml-1">
      {@product_code}
    </span>
    <span :if={!@plan_name} class="text-base-content/40">-</span>
    """
  end

  defp plan_badge_class("FREE"), do: "badge-ghost"
  defp plan_badge_class(_), do: "badge-info"

  # Accepts a preloaded User struct or a plain map with `:user_id`, `:email`,
  # `:username` (e.g. from `rate_limited_users/1`). Renders a link to the
  # generic admin user page with the first non-blank of email → username →
  # `user##{id}`. Returns "Anonymous" when no user is attached.
  defp user_label(assigns) do
    {id, label} = user_id_and_label(assigns[:user])
    assigns = assign(assigns, id: id, label: label)

    ~H"""
    <a
      :if={@id}
      href={~p"/admin/generic/#{@id}?resource=users"}
      class="link link-hover"
    >
      {@label}
    </a>
    <span :if={!@id} class="text-base-content/50">Anonymous</span>
    """
  end

  defp user_id_and_label(nil), do: {nil, "Anonymous"}

  defp user_id_and_label(%{} = u) do
    id = Map.get(u, :id) || Map.get(u, :user_id)
    label = blank_or(Map.get(u, :email)) || blank_or(Map.get(u, :username)) || "user##{id}"
    {id, label}
  end

  defp blank_or(nil), do: nil
  defp blank_or(""), do: nil
  defp blank_or(s) when is_binary(s), do: s

  defp status_badge(assigns) do
    {text, class} =
      if assigns.is_successful,
        do: {"OK", "badge-success"},
        else: {"Error", "badge-error"}

    assigns = assign(assigns, text: text, badge_class: class)

    ~H"""
    <span class={["badge badge-sm", @badge_class]}>{@text}</span>
    """
  end

  defp pagination(assigns) do
    ~H"""
    <div :if={@total_pages > 1} class="flex items-center justify-between mt-4 px-2">
      <button phx-click="prev_page" disabled={@page <= 1} class="btn btn-sm btn-soft">
        Previous
      </button>

      <span class="text-sm text-base-content/70">Page {@page} of {@total_pages}</span>

      <button phx-click="next_page" disabled={@page >= @total_pages} class="btn btn-sm btn-soft">
        Next
      </button>
    </div>
    """
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_bucket(nil, _), do: "-"

  defp format_bucket(%DateTime{} = dt, "hour"), do: Calendar.strftime(dt, "%Y-%m-%d %H:00")
  defp format_bucket(%DateTime{} = dt, _), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp format_bucket(%NaiveDateTime{} = ndt, "hour"), do: Calendar.strftime(ndt, "%Y-%m-%d %H:00")
  defp format_bucket(%NaiveDateTime{} = ndt, _), do: Calendar.strftime(ndt, "%Y-%m-%d")
  defp format_bucket(other, _), do: to_string(other)

  defp format_bytes(nil), do: "-"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  defp short_session(nil), do: "-"
  defp short_session(""), do: "-"
  defp short_session(sid) when byte_size(sid) <= 8, do: sid
  defp short_session(sid), do: binary_part(sid, 0, 8) <> "…"
end

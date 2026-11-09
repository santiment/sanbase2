defmodule SanbaseWeb.Admin.UserMetricsUsageLive do
  @moduledoc """
  Read-only admin page: which metrics, signals and GraphQL queries a single
  user has called, from the ClickHouse `api_call_data` table. Calls are split
  into API key (external API, Sansheets, scripts) and JWT (Sanbase webapp).

  Linked from the user's generic admin page (`/admin/generic/:id?resource=users`).
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.GenericAdminHTML, only: [stat_card: 1]

  alias Sanbase.Clickhouse.ApiCallData

  @periods [7, 30, 90, 365]
  @default_days 30
  @kinds ~w(metric signal query all)
  @default_kind "metric"
  @row_limit 1000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "User Metrics Usage")
     |> assign(:periods, @periods)
     |> assign(:row_limit, @row_limit)
     |> assign(:error, nil)
     |> assign(:user, nil)
     |> assign(:days, @default_days)
     |> assign(:kind, @default_kind)
     |> assign(:usage, nil)
     |> assign(:daily, nil)}
  end

  @impl true
  def handle_params(%{"user_id" => user_id} = params, _uri, socket) do
    days = parse_days(params["days"])
    kind = if params["kind"] in @kinds, do: params["kind"], else: @default_kind

    with {id, ""} <- Integer.parse(user_id),
         {:ok, user} <- Sanbase.Accounts.User.by_id(id) do
      socket =
        socket
        |> assign(:error, nil)
        |> assign(:kind, kind)
        |> maybe_load(user, days)

      {:noreply, socket}
    else
      _ ->
        {:noreply,
         socket
         |> assign(:user, nil)
         |> assign(:usage, nil)
         |> assign(:daily, nil)
         |> assign(:error, "User #{inspect(user_id)} not found")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :error, "Missing user_id parameter")}
  end

  # Changing only the kind filter re-filters the already loaded rows instead of
  # hitting ClickHouse again.
  defp maybe_load(socket, user, days) do
    loaded? =
      match?(%{id: id} when id == user.id, socket.assigns.user) and
        socket.assigns.days == days and socket.assigns.usage != nil

    if loaded? do
      socket
    else
      from = DateTime.utc_now() |> DateTime.add(-days, :day)

      socket
      |> assign(:user, user)
      |> assign(:days, days)
      |> assign_async(:usage, fn ->
        case ApiCallData.user_queries_usage(user.id, from, @row_limit) do
          {:ok, rows} -> {:ok, %{usage: Enum.map(rows, &classify/1)}}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> assign_async(:daily, fn ->
        case ApiCallData.user_daily_usage(user.id, from) do
          {:ok, rows} -> {:ok, %{daily: rows}}
          {:error, reason} -> {:error, reason}
        end
      end)
    end
  end

  defp parse_days(nil), do: @default_days

  defp parse_days(days) do
    case Integer.parse(days) do
      {d, ""} when d in @periods -> d
      _ -> @default_days
    end
  end

  @doc false
  def classify(%{query: "getMetric|" <> metric} = row),
    do: Map.merge(row, %{kind: "metric", name: metric})

  def classify(%{query: "getSignal|" <> signal} = row),
    do: Map.merge(row, %{kind: "signal", name: signal})

  def classify(%{query: query} = row),
    do: Map.merge(row, %{kind: "query", name: query || "(none)"})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-baseline justify-between gap-2 flex-wrap">
        <h1 class="text-xl font-semibold">User Metrics Usage</h1>
        <div :if={@user} class="flex gap-2">
          <.link
            navigate={~p"/admin/user_overview?user_id=#{@user.id}"}
            class="btn btn-sm btn-soft"
          >
            <.icon name="hero-user" class="size-4" /> Overview
          </.link>
          <.link href={~p"/admin/generic/#{@user.id}?resource=users"} class="btn btn-sm btn-soft">
            <.icon name="hero-cog-6-tooth" class="size-4" /> Admin record
          </.link>
        </div>
      </div>

      <div :if={@error} id="metrics-usage-error" class="alert alert-warning">{@error}</div>

      <section
        :if={@user}
        id="metrics-usage-user"
        class="bg-base-100 border border-base-300 rounded p-3 flex items-center gap-2 flex-wrap"
      >
        <span class="text-lg font-semibold">{@user.email || "(no email)"}</span>
        <span class="text-base-content/50">#{@user.id}</span>
        <span :if={@user.username} class="text-base-content/60">· {@user.username}</span>
      </section>

      <div :if={@user} class="flex items-center gap-4 flex-wrap">
        <div id="metrics-usage-periods" class="join">
          <.link
            :for={d <- @periods}
            id={"period-#{d}"}
            patch={~p"/admin/user_metrics_usage?user_id=#{@user.id}&days=#{d}&kind=#{@kind}"}
            class={["btn btn-sm join-item", d == @days && "btn-primary"]}
          >
            {d}d
          </.link>
        </div>
        <div id="metrics-usage-kinds" class="join">
          <.link
            :for={
              {k, label} <- [
                {"metric", "Metrics"},
                {"signal", "Signals"},
                {"query", "Other queries"},
                {"all", "All"}
              ]
            }
            id={"kind-#{k}"}
            patch={~p"/admin/user_metrics_usage?user_id=#{@user.id}&days=#{@days}&kind=#{k}"}
            class={["btn btn-sm join-item", k == @kind && "btn-primary"]}
          >
            {label}
          </.link>
        </div>
      </div>

      <.async_result :let={rows} :if={@user && @usage} assign={@usage}>
        <:loading>
          <div class="space-y-2 animate-pulse">
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
              <div :for={_ <- 1..4} class="h-8 bg-base-300 rounded"></div>
            </div>
            <div :for={_ <- 1..8} class="h-6 bg-base-300 rounded"></div>
          </div>
        </:loading>
        <:failed :let={reason}>
          <div class="alert alert-error">Could not load API calls: {inspect(reason)}</div>
        </:failed>

        <.usage_summary rows={rows} days={@days} />

        <.async_result :let={daily} assign={@daily}>
          <:loading>
            <div class="h-24 bg-base-300 rounded animate-pulse"></div>
          </:loading>
          <:failed :let={reason}>
            <div class="alert alert-error">Could not load daily activity: {inspect(reason)}</div>
          </:failed>
          <.daily_table rows={daily} />
        </.async_result>

        <.usage_table rows={filter_rows(rows, @kind)} kind={@kind} />

        <p :if={length(rows) >= @row_limit} class="text-xs text-warning">
          Showing the top {@row_limit} queries only.
        </p>
        <p class="text-xs text-base-content/50">
          Source: ClickHouse api_call_data, last {@days} days. API key = external API
          (scripts, Sansheets); JWT = Sanbase webapp.
        </p>
      </.async_result>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :days, :integer, required: true

  defp usage_summary(assigns) do
    metrics = Enum.filter(assigns.rows, &(&1.kind == "metric"))

    assigns =
      assigns
      |> assign(:distinct_metrics, length(metrics))
      |> assign(:metric_calls, Enum.sum_by(metrics, & &1.total_calls))
      |> assign(:apikey_calls, Enum.sum_by(assigns.rows, & &1.apikey_calls))
      |> assign(:jwt_calls, Enum.sum_by(assigns.rows, & &1.jwt_calls))

    ~H"""
    <div id="metrics-usage-summary" class="grid grid-cols-2 sm:grid-cols-4 gap-2">
      <.stat_card label="Distinct metrics" value={@distinct_metrics} />
      <.stat_card label="Metric calls" value={@metric_calls} />
      <.stat_card label="API key calls (all)" value={@apikey_calls} />
      <.stat_card label="JWT / webapp calls (all)" value={@jwt_calls} />
    </div>
    """
  end

  attr :rows, :list, required: true

  defp daily_table(assigns) do
    ~H"""
    <section class="space-y-1">
      <h2 class="text-sm font-semibold text-base-content/70">Daily activity</h2>
      <div class="max-h-72 overflow-y-auto bg-base-100 border border-base-300 rounded">
        <table id="metrics-usage-daily" class="table table-sm table-pin-rows">
          <thead>
            <tr>
              <th>Day (UTC)</th>
              <th>Auth</th>
              <th class="text-right">Calls</th>
              <th class="text-right">Distinct metrics</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@rows == []}>
              <td colspan="4" class="text-center text-base-content/50 py-4">
                No calls in this period.
              </td>
            </tr>
            <tr
              :for={row <- @rows}
              id={"daily-row-#{row.date}-#{row.auth_method}"}
              class="hover"
            >
              <td class="tabular-nums whitespace-nowrap">{Date.to_iso8601(row.date)}</td>
              <td>
                <span class={["badge badge-sm", auth_class(row.auth_method)]}>
                  {row.auth_method}
                </span>
              </td>
              <td class="text-right tabular-nums">{format_int(row.calls)}</td>
              <td class="text-right tabular-nums">{format_int(row.distinct_metrics)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp auth_class("apikey"), do: "badge-primary"
  defp auth_class("jwt"), do: "badge-ghost"
  defp auth_class(_), do: "badge-neutral"

  attr :rows, :list, required: true
  attr :kind, :string, required: true

  defp usage_table(assigns) do
    ~H"""
    <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
      <table id="metrics-usage-table" class="table table-sm table-zebra">
        <thead>
          <tr>
            <th :if={@kind == "all"}>Type</th>
            <th>Name</th>
            <th class="text-right">Total</th>
            <th class="text-right">API key</th>
            <th class="text-right">JWT</th>
            <th class="text-right">Other</th>
            <th>Last called (UTC)</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td colspan="7" class="text-center text-base-content/50 py-6">
              No calls in this period.
            </td>
          </tr>
          <tr :for={row <- @rows} id={"usage-row-#{row.kind}-#{row.name}"} class="hover">
            <td :if={@kind == "all"}>
              <span class={["badge badge-sm", kind_class(row.kind)]}>{row.kind}</span>
            </td>
            <td class="font-mono text-xs">{row.name}</td>
            <td class="text-right tabular-nums font-semibold">{format_int(row.total_calls)}</td>
            <td class="text-right tabular-nums">{format_int(row.apikey_calls)}</td>
            <td class="text-right tabular-nums">{format_int(row.jwt_calls)}</td>
            <td class="text-right tabular-nums text-base-content/60">
              {format_int(row.other_calls)}
            </td>
            <td class="text-xs tabular-nums whitespace-nowrap">
              {Calendar.strftime(row.last_called_at, "%Y-%m-%d %H:%M")}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp filter_rows(rows, "all"), do: rows
  defp filter_rows(rows, kind), do: Enum.filter(rows, &(&1.kind == kind))

  defp kind_class("metric"), do: "badge-primary"
  defp kind_class("signal"), do: "badge-secondary"
  defp kind_class(_), do: "badge-ghost"

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_int(n), do: to_string(n)
end

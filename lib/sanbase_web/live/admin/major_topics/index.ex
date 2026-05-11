defmodule SanbaseWeb.Admin.MajorTopicsLive.Index do
  use SanbaseWeb, :live_view

  alias Sanbase.MajorTopics

  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]

  @default_page_size 25

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Major Topics")
     |> assign_pagination(params)}
  end

  def handle_params(params, _uri, socket), do: {:noreply, assign_pagination(socket, params)}

  defp assign_pagination(socket, params) do
    page = parse_int(Map.get(params, "page"), 1)
    page_size = parse_int(Map.get(params, "page_size"), @default_page_size) |> max(1)

    total_count = MajorTopics.count_batches()
    total_pages = max(1, div(total_count + page_size - 1, page_size))
    page = page |> max(1) |> min(total_pages)

    batches = MajorTopics.list_batches(page: page, page_size: page_size)

    socket
    |> assign(:batches, batches)
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-3xl font-bold">Major Topics</h1>
    <div class="p-6 max-w-7xl">
      <p class="text-sm text-base-content/70 mb-4">
        Daily snapshot of crypto narratives fetched from ClickHouse. The most recent draft batch
        can be moderated (edit labels, remove rows) and published; only the latest published
        batch is exposed via the public GraphQL API.
      </p>

      <div :if={@batches == []} class="text-center py-12 bg-base-200 rounded-box">
        <h3 class="mt-2 text-sm font-medium">No batches fetched yet</h3>
        <p class="mt-1 text-sm text-base-content/60">
          The daily 05:00 UTC cron will produce a batch automatically.
        </p>
      </div>

      <div :if={@batches != []} class="rounded-box border border-base-300 overflow-hidden">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th>Interval</th>
              <th>Source</th>
              <th>Version</th>
              <th>State</th>
              <th>Fetched</th>
              <th>Published</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={batch <- @batches}>
              <td class="font-mono text-xs">
                {Date.to_iso8601(batch.interval_start)} → {Date.to_iso8601(batch.interval_end)}
              </td>
              <td>{batch.source}</td>
              <td>{batch.version}</td>
              <td>
                <span class={["badge badge-sm", state_badge(batch.state)]}>{batch.state}</span>
              </td>
              <td class="text-xs">{Calendar.strftime(batch.fetched_at, "%Y-%m-%d %H:%M UTC")}</td>
              <td class="text-xs">
                <span :if={batch.published_at}>
                  {Calendar.strftime(batch.published_at, "%Y-%m-%d %H:%M UTC")}
                </span>
                <span :if={!batch.published_at} class="text-base-content/40">—</span>
              </td>
              <td class="text-right">
                <.link
                  navigate={~p"/admin/major_topics/#{batch.id}"}
                  class="link link-primary text-sm font-medium"
                >
                  Open
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        :if={@batches != []}
        class="mt-4 flex items-center justify-between text-sm text-base-content/70"
      >
        <div>
          <span class="font-medium">Total:</span> {@total_count}
          <span class="mx-2">•</span>
          <span>Page {@page} of {@total_pages}</span>
        </div>
        <div class="join">
          <.link
            patch={~p"/admin/major_topics?#{[page: max(@page - 1, 1), page_size: @page_size]}"}
            class={["btn btn-sm join-item", @page == 1 && "btn-disabled"]}
            aria-disabled={@page == 1}
          >
            Prev
          </.link>
          <.link
            patch={
              ~p"/admin/major_topics?#{[page: min(@page + 1, @total_pages), page_size: @page_size]}"
            }
            class={["btn btn-sm join-item", @page == @total_pages && "btn-disabled"]}
            aria-disabled={@page == @total_pages}
          >
            Next
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp state_badge("published"), do: "badge-success"
  defp state_badge("draft"), do: "badge-warning"
  defp state_badge(_), do: "badge-neutral"
end

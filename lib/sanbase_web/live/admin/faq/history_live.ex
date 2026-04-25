defmodule SanbaseWeb.Admin.FaqLive.History do
  use SanbaseWeb, :live_view

  alias Sanbase.Knowledge.QuestionAnswerLog

  @default_page_size 10

  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "FAQ Question/Answer History")
      |> assign_pagination(params)

    {:ok, socket}
  end

  def handle_params(params, _uri, socket), do: {:noreply, assign_pagination(socket, params)}

  defp assign_pagination(socket, params) do
    page = parse_int(Map.get(params, "page"), 1)
    page_size = parse_int(Map.get(params, "page_size"), @default_page_size)

    total_count = Sanbase.Repo.aggregate(QuestionAnswerLog, :count, :id)
    total_pages = max(1, div(total_count + page_size - 1, page_size))
    page = page |> max(1) |> min(total_pages)

    entries = QuestionAnswerLog.list_entries(page, page_size)

    socket
    |> assign(:entries, entries)
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-3xl font-bold">FAQ Question/Answer History</h1>
    <div class="p-6 max-w-7xl">
      <.history_pager page={@page} page_size={@page_size} total_count={@total_count} total_pages={@total_pages} />
      <%= if @entries == [] do %>
        <div class="text-center py-12 bg-base-200 rounded-box">
          <.icon name="hero-document-text" class="mx-auto size-12 text-base-content/40" />
          <h3 class="mt-2 text-sm font-medium">No question/answer history</h3>
          <p class="mt-1 text-sm text-base-content/60">There are no question/answer logs yet.</p>
        </div>
      <% else %>
        <div class="rounded-box border border-base-300 overflow-hidden">
          <ul role="list" class="divide-y divide-base-300">
            <li
              :for={entry <- @entries}
              class={["hover:bg-base-200", !entry.is_successful && "bg-error/10"]}
            >
              <div class="px-4 py-4 flex items-center justify-between">
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-medium truncate">{entry.question}</h3>
                  <div class="mt-1 flex items-center flex-wrap gap-2 text-sm text-base-content/60">
                    <time datetime={Calendar.strftime(entry.inserted_at, "%Y-%m-%dT%H:%M:%SZ")}>
                      Asked {Calendar.strftime(entry.inserted_at, "%B %d, %Y at %I:%M %p")}
                    </time>
                    <%= if entry.user do %>
                      <span>•</span>
                      <span>By {entry.user.name || entry.user.email || "Anon"}</span>
                    <% end %>
                    <span>•</span>
                    <span class={[
                      "badge badge-sm",
                      entry.question_type == "ask_ai" && "badge-info",
                      entry.question_type == "smart_search" && "badge-success"
                    ]}>
                      {String.replace(entry.question_type, "_", " ")}
                    </span>
                    <%= if !entry.is_successful do %>
                      <span>•</span>
                      <span class="badge badge-sm badge-error">Failed</span>
                    <% end %>
                  </div>
                </div>
                <div class="flex items-center gap-2 ml-4">
                  <.link navigate={~p"/admin/faq/history/#{entry.id}"} class="link link-primary text-sm font-medium">
                    View
                  </.link>
                </div>
              </div>
            </li>
          </ul>
        </div>
        <div class="mt-4">
          <.history_pager page={@page} page_size={@page_size} total_count={@total_count} total_pages={@total_pages} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :total_count, :integer, required: true
  attr :total_pages, :integer, required: true

  defp history_pager(assigns) do
    ~H"""
    <div class="flex items-center justify-between text-sm text-base-content/70 mb-4">
      <div>
        <span class="font-medium">Total:</span> {@total_count}
        <span class="mx-2">•</span>
        <span>Page {@page} of {@total_pages}</span>
      </div>
      <div class="join">
        <.link
          patch={~p"/admin/faq/history?#{[page: max(@page - 1, 1), page_size: @page_size]}"}
          class={["btn btn-sm join-item", @page == 1 && "btn-disabled"]}
          aria-disabled={@page == 1}
        >
          Prev
        </.link>
        <.link
          patch={~p"/admin/faq/history?#{[page: min(@page + 1, @total_pages), page_size: @page_size]}"}
          class={["btn btn-sm join-item", @page == @total_pages && "btn-disabled"]}
          aria-disabled={@page == @total_pages}
        >
          Next
        </.link>
      </div>
    </div>
    """
  end
end

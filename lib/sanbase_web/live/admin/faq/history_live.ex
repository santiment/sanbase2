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
    <h1 class="text-3xl font-bold text-gray-900">FAQ Question/Answer History</h1>
    <div class="p-6 max-w-7xl">
      <div class="mb-4 flex items-center justify-between text-sm text-gray-600">
        <div>
          <span class="font-medium">Total:</span> {@total_count}
          <span class="mx-2">•</span>
          <span>Page {@page} of {@total_pages}</span>
        </div>
        <div class="flex items-center gap-2">
          <.link
            patch={~p"/admin/faq/history?#{[page: max(@page - 1, 1), page_size: @page_size]}"}
            class={[
              "px-3 py-1 rounded border transition-colors",
              @page == 1 && "text-gray-400 border-gray-200 cursor-not-allowed",
              @page > 1 && "text-gray-700 border-gray-300 hover:bg-gray-50"
            ]}
            aria-disabled={@page == 1}
          >
            Prev
          </.link>
          <.link
            patch={
              ~p"/admin/faq/history?#{[page: min(@page + 1, @total_pages), page_size: @page_size]}"
            }
            class={[
              "px-3 py-1 rounded border transition-colors",
              @page == @total_pages && "text-gray-400 border-gray-200 cursor-not-allowed",
              @page < @total_pages && "text-gray-700 border-gray-300 hover:bg-gray-50"
            ]}
            aria-disabled={@page == @total_pages}
          >
            Next
          </.link>
        </div>
      </div>
      <%= if @entries == [] do %>
        <div class="text-center py-12 bg-gray-50 rounded-lg">
          <svg
            class="mx-auto h-12 w-12 text-gray-400"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
            />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No question/answer history</h3>
          <p class="mt-1 text-sm text-gray-500">There are no question/answer logs yet.</p>
        </div>
      <% else %>
        <div class="bg-white shadow overflow-hidden sm:rounded-md">
          <ul role="list" class="divide-y divide-gray-200">
            <li
              :for={entry <- @entries}
              class={[
                "hover:bg-gray-50",
                !entry.is_successful && "bg-red-50"
              ]}
            >
              <div class="px-4 py-4 flex items-center justify-between">
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-medium text-gray-900 truncate">
                    {entry.question}
                  </h3>
                  <div class="mt-1 flex items-center text-sm text-gray-500">
                    <time datetime={Calendar.strftime(entry.inserted_at, "%Y-%m-%dT%H:%M:%SZ")}>
                      Asked {Calendar.strftime(entry.inserted_at, "%B %d, %Y at %I:%M %p")}
                    </time>
                    <%= if entry.user do %>
                      <span class="mx-2">•</span>
                      <span>By {entry.user.name || entry.user.email || "Anon"}</span>
                    <% end %>
                    <span class="mx-2">•</span>
                    <span class={[
                      "inline-flex items-center px-2 py-1 rounded-full text-xs font-medium",
                      entry.question_type == "ask_ai" && "bg-blue-100 text-blue-800",
                      entry.question_type == "smart_search" && "bg-green-100 text-green-800"
                    ]}>
                      {String.replace(entry.question_type, "_", " ")}
                    </span>
                    <%= if !entry.is_successful do %>
                      <span class="mx-2">•</span>
                      <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-red-100 text-red-800">
                        Failed
                      </span>
                    <% end %>
                  </div>
                </div>
                <div class="flex items-center space-x-2 ml-4">
                  <.link
                    navigate={~p"/admin/faq/history/#{entry.id}"}
                    class="text-blue-600 hover:text-blue-800 font-medium text-sm"
                  >
                    View
                  </.link>
                </div>
              </div>
            </li>
          </ul>
        </div>
        <div class="mt-4 flex items-center justify-between text-sm text-gray-600">
          <div>
            <span class="font-medium">Total:</span> {@total_count}
            <span class="mx-2">•</span>
            <span>Page {@page} of {@total_pages}</span>
          </div>
          <div class="flex items-center gap-2">
            <.link
              patch={~p"/admin/faq/history?#{[page: max(@page - 1, 1), page_size: @page_size]}"}
              class={[
                "px-3 py-1 rounded border transition-colors",
                @page == 1 && "text-gray-400 border-gray-200 cursor-not-allowed",
                @page > 1 && "text-gray-700 border-gray-300 hover:bg-gray-50"
              ]}
              aria-disabled={@page == 1}
            >
              Prev
            </.link>
            <.link
              patch={
                ~p"/admin/faq/history?#{[page: min(@page + 1, @total_pages), page_size: @page_size]}"
              }
              class={[
                "px-3 py-1 rounded border transition-colors",
                @page == @total_pages && "text-gray-400 border-gray-200 cursor-not-allowed",
                @page < @total_pages && "text-gray-700 border-gray-300 hover:bg-gray-50"
              ]}
              aria-disabled={@page == @total_pages}
            >
              Next
            </.link>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

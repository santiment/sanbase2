defmodule SanbaseWeb.Admin.FaqLive.Index do
  use SanbaseWeb, :live_view

  alias Sanbase.Knowledge.Faq

  @default_page_size 20

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "FAQ Management")

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    page = parse_int(Map.get(params, "page"), 1)
    page_size = parse_int(Map.get(params, "page_size"), @default_page_size)

    total_count = Faq.count_entries()
    total_pages = max(1, div(total_count + page_size - 1, page_size))
    page = page |> max(1) |> min(total_pages)

    entries = Faq.list_entries(page, page_size)

    socket =
      socket
      |> assign(:entries, entries)
      |> assign(:page, page)
      |> assign(:page_size, page_size)
      |> assign(:total_count, total_count)
      |> assign(:total_pages, total_pages)

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    entry = Faq.get_entry!(id)
    {:ok, _} = Faq.delete_entry(entry)

    total_count = Faq.count_entries()

    total_pages =
      max(1, div(total_count + socket.assigns.page_size - 1, socket.assigns.page_size))

    page = socket.assigns.page |> min(total_pages)

    {:noreply,
     socket
     |> put_flash(:info, "FAQ entry deleted successfully")
     |> push_patch(to: ~p"/admin/faq?#{[page: page, page_size: socket.assigns.page_size]}")}
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-3xl font-bold text-gray-900">FAQ Management</h1>
    <div class="p-6 max-w-7xl">
      <div class="flex items-start gap-x-2 mb-6">
        <.link
          navigate={~p"/admin/faq/new"}
          class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
        >
          New FAQ Entry
        </.link>

        <.link
          navigate={~p"/admin/faq/ask"}
          class="bg-amber-600 hover:bg-amber-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
        >
          Ask
        </.link>
      </div>
      <div class="mb-4 flex items-center justify-between text-sm text-gray-600">
        <div>
          <span class="font-medium">Total:</span> {@total_count}
          <span class="mx-2">•</span>
          <span>Page {@page} of {@total_pages}</span>
        </div>
        <div class="flex items-center gap-2">
          <.link
            patch={~p"/admin/faq?#{[page: max(@page - 1, 1), page_size: @page_size]}"}
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
            patch={~p"/admin/faq?#{[page: min(@page + 1, @total_pages), page_size: @page_size]}"}
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
          <h3 class="mt-2 text-sm font-medium text-gray-900">No FAQ entries</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by creating a new FAQ entry.</p>
          <div class="mt-6">
            <.link
              navigate={~p"/admin/faq/new"}
              class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
            >
              New FAQ Entry
            </.link>
          </div>
        </div>
      <% else %>
        <div class="bg-white shadow overflow-hidden sm:rounded-md">
          <ul role="list" class="divide-y divide-gray-200">
            <li :for={entry <- @entries} class="hover:bg-gray-50">
              <div class="px-4 py-4 flex items-center justify-between">
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-medium text-gray-900 truncate">
                    {entry.question}
                  </h3>
                  <%= if entry.tags && length(entry.tags) > 0 do %>
                    <div class="mt-2 flex flex-wrap gap-1">
                      <span :for={tag <- entry.tags}>
                        <.tag_badge tag={tag.name} />
                      </span>
                    </div>
                  <% end %>
                  <div class="mt-1 flex items-center text-sm text-gray-500">
                    <time datetime={entry.updated_at}>
                      Updated {Calendar.strftime(entry.updated_at, "%B %d, %Y at %I:%M %p")}
                    </time>
                    <%= if entry.source_url do %>
                      <span class="mx-1">•</span>
                      <a
                        href={entry.source_url}
                        target="_blank"
                        class="text-blue-600 hover:text-blue-800"
                      >
                        Source
                      </a>
                    <% end %>
                  </div>
                </div>
                <div class="flex items-center space-x-2 ml-4">
                  <.link
                    navigate={~p"/admin/faq/#{entry.id}"}
                    class="text-blue-600 hover:text-blue-800 font-medium text-sm"
                  >
                    View
                  </.link>
                  <.link
                    navigate={~p"/admin/faq/#{entry.id}/edit"}
                    class="text-yellow-600 hover:text-yellow-800 font-medium text-sm"
                  >
                    Edit
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={entry.id}
                    data-confirm="Are you sure you want to delete this FAQ entry?"
                    class="text-red-600 hover:text-red-800 font-medium text-sm"
                  >
                    Delete
                  </button>
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
              patch={~p"/admin/faq?#{[page: max(@page - 1, 1), page_size: @page_size]}"}
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
              patch={~p"/admin/faq?#{[page: min(@page + 1, @total_pages), page_size: @page_size]}"}
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

  defp parse_int(nil, default), do: default
  defp parse_int(value, default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp tag_badge(assigns) do
    colors_class =
      case assigns.tag do
        "code" -> "text-indigo-400 bg-indigo-400/10"
        "subscription" -> "text-green-400 bg-green-400/10"
        "payment" -> "text-yellow-400 bg-green-400/10"
        "api" -> "text-blue-400 bg-blue-400/10"
        "sanbase" -> "text-red-400 bg-red-400/10"
        "metrics" -> "text-purple-400 bg-purple-400/10"
      end

    assigns = assign(assigns, :colors_class, colors_class)

    ~H"""
    <span class={["inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ", @colors_class]}>
      {@tag}
    </span>
    """
  end
end

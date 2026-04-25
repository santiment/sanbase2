defmodule SanbaseWeb.Admin.FaqLive.Index do
  use SanbaseWeb, :live_view

  alias Sanbase.Knowledge.Faq
  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]

  @default_page_size 10

  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "FAQ Management")
      |> assign_pagination(params)

    {:ok, socket}
  end

  def handle_params(params, _uri, socket), do: {:noreply, assign_pagination(socket, params)}

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

  defp assign_pagination(socket, params) do
    page = parse_int(Map.get(params, "page"), 1)
    page_size = parse_int(Map.get(params, "page_size"), @default_page_size) |> max(1)

    total_count = Faq.count_entries()
    total_pages = max(1, div(total_count + page_size - 1, page_size))
    page = page |> max(1) |> min(total_pages)

    entries = Faq.list_entries(page, page_size)

    socket
    |> assign(:entries, entries)
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-3xl font-bold">FAQ Management</h1>
    <div class="p-6 max-w-7xl">
      <div class="flex items-start gap-x-2 mb-6">
        <.link navigate={~p"/admin/faq/history"} class="btn btn-sm btn-secondary">
          History
        </.link>
        <.link navigate={~p"/admin/faq/new"} class="btn btn-sm btn-primary">
          New FAQ Entry
        </.link>
        <.link navigate={~p"/admin/faq/ask"} class="btn btn-sm btn-warning">
          Ask
        </.link>
      </div>
      <.pagination
        page={@page}
        page_size={@page_size}
        total_count={@total_count}
        total_pages={@total_pages}
      />
      <%= if @entries == [] do %>
        <div class="text-center py-12 bg-base-200 rounded-box">
          <.icon name="hero-document-text" class="mx-auto size-12 text-base-content/40" />
          <h3 class="mt-2 text-sm font-medium">No FAQ entries</h3>
          <p class="mt-1 text-sm text-base-content/60">Get started by creating a new FAQ entry.</p>
          <div class="mt-6">
            <.link navigate={~p"/admin/faq/new"} class="btn btn-sm btn-primary">
              New FAQ Entry
            </.link>
          </div>
        </div>
      <% else %>
        <div class="rounded-box border border-base-300 overflow-hidden">
          <ul role="list" class="divide-y divide-base-300">
            <li :for={entry <- @entries} class="hover:bg-base-200">
              <div class="px-4 py-4 flex items-center justify-between">
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-medium truncate">{entry.question}</h3>
                  <%= if entry.tags && length(entry.tags) > 0 do %>
                    <div class="mt-2 flex flex-wrap gap-1">
                      <span :for={tag <- entry.tags}>
                        <.tag_badge tag={tag.name} />
                      </span>
                    </div>
                  <% end %>
                  <div class="mt-1 flex items-center text-sm text-base-content/60">
                    <time datetime={entry.updated_at}>
                      Updated {Calendar.strftime(entry.updated_at, "%B %d, %Y at %I:%M %p")}
                    </time>
                    <%= if entry.source_url do %>
                      <span class="mx-1">•</span>
                      <a href={entry.source_url} target="_blank" class="link link-primary">
                        Source
                      </a>
                    <% end %>
                  </div>
                </div>
                <div class="flex items-center gap-2 ml-4">
                  <.link navigate={~p"/admin/faq/#{entry.id}"} class="link link-primary text-sm font-medium">
                    View
                  </.link>
                  <.link navigate={~p"/admin/faq/#{entry.id}/edit"} class="link text-warning text-sm font-medium">
                    Edit
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={entry.id}
                    data-confirm="Are you sure you want to delete this FAQ entry?"
                    class="link text-error text-sm font-medium"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </li>
          </ul>
        </div>
        <.pagination
          page={@page}
          page_size={@page_size}
          total_count={@total_count}
          total_pages={@total_pages}
          class="mt-4"
        />
      <% end %>
    </div>
    """
  end

  attr :page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :total_count, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :class, :string, default: "mb-4"

  defp pagination(assigns) do
    ~H"""
    <div class={["flex items-center justify-between text-sm text-base-content/70", @class]}>
      <div>
        <span class="font-medium">Total:</span> {@total_count}
        <span class="mx-2">•</span>
        <span>Page {@page} of {@total_pages}</span>
      </div>
      <div class="join">
        <.link
          patch={~p"/admin/faq?#{[page: max(@page - 1, 1), page_size: @page_size]}"}
          class={["btn btn-sm join-item", @page == 1 && "btn-disabled"]}
          aria-disabled={@page == 1}
        >
          Prev
        </.link>
        <.link
          patch={~p"/admin/faq?#{[page: min(@page + 1, @total_pages), page_size: @page_size]}"}
          class={["btn btn-sm join-item", @page == @total_pages && "btn-disabled"]}
          aria-disabled={@page == @total_pages}
        >
          Next
        </.link>
      </div>
    </div>
    """
  end

  defp tag_badge(assigns) do
    colors_class =
      case assigns.tag do
        "code" -> "badge-secondary"
        "subscription" -> "badge-success"
        "payment" -> "badge-warning"
        "api" -> "badge-info"
        "sanbase" -> "badge-error"
        "metrics" -> "badge-accent"
      end

    assigns = assign(assigns, :colors_class, colors_class)

    ~H"""
    <span class={["badge badge-sm badge-soft", @colors_class]}>{@tag}</span>
    """
  end
end

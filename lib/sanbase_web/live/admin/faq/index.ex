defmodule SanbaseWeb.Admin.FaqLive.Index do
  use SanbaseWeb, :live_view

  alias Sanbase.Knowledge.Faq
  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]
  import SanbaseWeb.Admin.FaqLive.Nav, only: [nav: 1]

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

    %{status: status, page_size: page_size} = socket.assigns
    total_count = Faq.count_entries(status: status)
    total_pages = max(1, div(total_count + page_size - 1, page_size))
    page = socket.assigns.page |> min(total_pages)

    {:noreply,
     socket
     |> put_flash(:info, "FAQ entry deleted successfully")
     |> push_patch(to: ~p"/admin/faq?#{list_params(page, page_size, status)}")}
  end

  defp assign_pagination(socket, params) do
    status = parse_status(Map.get(params, "status"))
    page = parse_int(Map.get(params, "page"), 1)
    page_size = parse_int(Map.get(params, "page_size"), @default_page_size) |> max(1)

    total_count = Faq.count_entries(status: status)
    total_pages = max(1, div(total_count + page_size - 1, page_size))
    page = page |> max(1) |> min(total_pages)

    entries = Faq.list_entries(page, page_size, status: status)

    socket
    |> assign(:entries, entries)
    |> assign(:status, status)
    |> assign(:drafts_count, Faq.count_entries(status: :draft))
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
  end

  defp parse_status("draft"), do: :draft
  defp parse_status("published"), do: :published
  defp parse_status(_), do: nil

  # Query params for the list URL; the status is left out when listing everything.
  defp list_params(page, page_size, nil), do: [page: page, page_size: page_size]

  defp list_params(page, page_size, status),
    do: [page: page, page_size: page_size, status: status]

  def render(assigns) do
    ~H"""
    <.nav active={:index} />
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex items-center justify-between gap-4 mb-6">
        <div>
          <h1 class="text-2xl font-bold">FAQ Entries</h1>
          <p class="mt-1 text-sm text-base-content/60">Manage the knowledge base entries.</p>
        </div>
        <.link navigate={~p"/admin/faq/new"} class="btn btn-sm btn-primary">
          <.icon name="hero-plus" class="size-4" /> New Entry
        </.link>
      </div>
      <div id="faq-status-tabs" role="tablist" class="flex items-center gap-1 mb-4">
        <.status_tab status={nil} active={@status} page_size={@page_size}>All</.status_tab>
        <.status_tab status={:published} active={@status} page_size={@page_size}>
          Published
        </.status_tab>
        <.status_tab status={:draft} active={@status} page_size={@page_size}>
          Drafts
          <span
            :if={@drafts_count > 0}
            class="ml-1 inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-warning text-warning-content text-xs font-semibold"
          >
            {@drafts_count}
          </span>
        </.status_tab>
      </div>
      <.pagination
        status={@status}
        page={@page}
        page_size={@page_size}
        total_count={@total_count}
        total_pages={@total_pages}
      />
      <div
        :if={@entries == [] and @status == :draft}
        id="faq-no-drafts"
        class="text-center py-12 bg-base-200 rounded-box"
      >
        <.icon name="hero-check-circle" class="mx-auto size-12 text-success/60" />
        <h3 class="mt-2 text-sm font-medium">No drafts waiting for review</h3>
        <p class="mt-1 text-sm text-base-content/60">
          Drafts created through the knowledge MCP show up here.
        </p>
      </div>
      <div
        :if={@entries == [] and @status != :draft}
        class="text-center py-12 bg-base-200 rounded-box"
      >
        <.icon name="hero-document-text" class="mx-auto size-12 text-base-content/40" />
        <h3 class="mt-2 text-sm font-medium">No FAQ entries</h3>
        <p class="mt-1 text-sm text-base-content/60">Get started by creating a new FAQ entry.</p>
        <div class="mt-6">
          <.link navigate={~p"/admin/faq/new"} class="btn btn-sm btn-primary">
            New FAQ Entry
          </.link>
        </div>
      </div>
      <div :if={@entries != []} class="rounded-box border border-base-300 overflow-hidden">
        <ul id="faq-entries" role="list" class="divide-y divide-base-300">
          <li
            :for={entry <- @entries}
            id={"faq-entry-#{entry.id}"}
            class="hover:bg-base-200 transition-colors"
          >
            <div class="px-4 py-4 flex items-center justify-between">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 min-w-0">
                  <span
                    :if={entry.status == :draft}
                    class="badge badge-sm badge-warning badge-soft shrink-0"
                  >
                    Draft
                  </span>
                  <h3 class="text-lg font-medium truncate">{entry.question}</h3>
                </div>
                <div
                  :if={entry.tags && length(entry.tags) > 0}
                  class="mt-2 flex flex-wrap gap-1"
                >
                  <span :for={tag <- entry.tags}>
                    <.tag_badge tag={tag.name} />
                  </span>
                </div>
                <div class="mt-1 flex items-center text-sm text-base-content/60">
                  <time datetime={entry.updated_at}>
                    Updated {Calendar.strftime(entry.updated_at, "%B %d, %Y at %I:%M %p")}
                  </time>
                  <span :if={entry.status == :draft} class="mx-1">•</span>
                  <span :if={entry.status == :draft}>
                    {draft_author(entry)}
                  </span>
                  <span :if={entry.source_url} class="mx-1">•</span>
                  <a
                    :if={entry.source_url}
                    href={entry.source_url}
                    target="_blank"
                    class="link link-primary"
                  >
                    Source
                  </a>
                </div>
              </div>
              <div class="flex items-center gap-2 ml-4">
                <.link
                  navigate={~p"/admin/faq/#{entry.id}"}
                  class="link link-primary text-sm font-medium"
                >
                  View
                </.link>
                <.link
                  navigate={~p"/admin/faq/#{entry.id}/edit"}
                  class="link text-warning text-sm font-medium"
                >
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
        :if={@entries != []}
        status={@status}
        page={@page}
        page_size={@page_size}
        total_count={@total_count}
        total_pages={@total_pages}
        class="mt-4"
      />
    </div>
    """
  end

  attr :status, :atom, required: true
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
          patch={~p"/admin/faq?#{list_params(max(@page - 1, 1), @page_size, @status)}"}
          class={["btn btn-sm join-item", @page == 1 && "btn-disabled"]}
          aria-disabled={@page == 1}
        >
          Prev
        </.link>
        <.link
          patch={~p"/admin/faq?#{list_params(min(@page + 1, @total_pages), @page_size, @status)}"}
          class={["btn btn-sm join-item", @page == @total_pages && "btn-disabled"]}
          aria-disabled={@page == @total_pages}
        >
          Next
        </.link>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :active, :atom, required: true
  attr :page_size, :integer, required: true
  slot :inner_block, required: true

  defp status_tab(assigns) do
    ~H"""
    <.link
      patch={~p"/admin/faq?#{list_params(1, @page_size, @status)}"}
      id={"faq-tab-#{@status || :all}"}
      role="tab"
      aria-selected={@status == @active}
      class={[
        "inline-flex items-center px-3 py-1.5 text-sm font-medium rounded-lg transition-colors",
        @status == @active && "bg-primary/10 text-primary",
        @status != @active && "text-base-content/60 hover:text-base-content hover:bg-base-200"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp draft_author(%{origin: origin, created_by: created_by}) do
    by =
      case created_by do
        %Sanbase.Accounts.User{email: email} when is_binary(email) -> " by #{email}"
        _ -> ""
      end

    via = if origin == :mcp, do: " via Claude", else: ""
    "Draft#{via}#{by}"
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
        _ -> "badge-neutral"
      end

    assigns = assign(assigns, :colors_class, colors_class)

    ~H"""
    <span class={["badge badge-sm badge-soft", @colors_class]}>{@tag}</span>
    """
  end
end

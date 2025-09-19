defmodule SanbaseWeb.Admin.FaqLive.Show do
  use SanbaseWeb, :live_view

  alias Sanbase.Knowledge.Faq

  def mount(%{"id" => id}, _session, socket) do
    entry = Faq.get_entry!(id)

    socket =
      socket
      |> assign(:entry, entry)
      |> assign(:page_title, "FAQ Entry: #{entry.question}")

    {:ok, socket}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Faq.delete_entry(socket.assigns.entry)

    socket =
      socket
      |> put_flash(:info, "FAQ entry deleted successfully")
      |> push_navigate(to: ~p"/admin/faq")

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto">
      <div class="flex justify-between items-start mb-6">
        <div>
          <.link
            navigate={~p"/admin/faq"}
            class="text-blue-600 hover:text-blue-800 font-medium text-sm mb-2 inline-block"
          >
            ← Back to FAQ List
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">{@entry.question}</h1>
        </div>
        <div class="flex items-center space-x-3">
          <.link
            navigate={~p"/admin/faq/#{@entry.id}/edit"}
            class="bg-yellow-600 hover:bg-yellow-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this FAQ entry?"
            class="bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
          >
            Delete
          </button>
        </div>
      </div>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-200">
          <h3 class="text-lg font-medium text-gray-900">Answer</h3>
        </div>
        <div class="px-6 py-6">
          <div class="prose max-w-none text-gray-900">
            {Phoenix.HTML.raw(@entry.answer_html)}
          </div>
        </div>
      </div>

      <div class="mt-6 bg-gray-50 rounded-lg p-4">
        <dl class="grid grid-cols-1 gap-x-4 gap-y-4 sm:grid-cols-2">
          <%= if @entry.source_url do %>
            <div>
              <dt class="text-sm font-medium text-gray-500">Source URL</dt>
              <dd class="mt-1 text-sm text-gray-900">
                <a
                  href={@entry.source_url}
                  target="_blank"
                  class="text-blue-600 hover:text-blue-800 break-all"
                >
                  {@entry.source_url}
                </a>
              </dd>
            </div>
          <% end %>
          <div>
            <dt class="text-sm font-medium text-gray-500">Created</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {Calendar.strftime(@entry.inserted_at, "%B %d, %Y at %I:%M %p UTC")}
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Last Updated</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {Calendar.strftime(@entry.updated_at, "%B %d, %Y at %I:%M %p UTC")}
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end
end

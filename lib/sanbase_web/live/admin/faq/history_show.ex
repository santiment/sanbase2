defmodule SanbaseWeb.Admin.FaqLive.HistoryShow do
  use SanbaseWeb, :live_view

  alias Sanbase.Knowledge.QuestionAnswerLog

  def mount(%{"id" => id}, _session, socket) do
    {:ok, entry} = QuestionAnswerLog.by_id(id)
    answer_html = Earmark.as_html!(entry.answer || "")

    socket =
      socket
      |> assign(:entry, entry)
      |> assign(:answer_html, answer_html)
      |> assign(:page_title, "Question/Answer Log Entry")

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto">
      <div class="flex justify-between items-start mb-6">
        <div>
          <.link
            navigate={~p"/admin/faq/history"}
            class="text-blue-600 hover:text-blue-800 font-medium text-sm mb-2 inline-block"
          >
            ← Back to History
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">{@entry.question}</h1>
        </div>
      </div>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-200">
          <h3 class="text-lg font-medium text-gray-900">Answer</h3>
        </div>
        <div class="px-6 py-6">
          <div class="prose max-w-none text-gray-900">
            {Phoenix.HTML.raw(@answer_html)}
          </div>
        </div>
      </div>

      <div class="mt-6 grid grid-cols-1 gap-x-4 gap-y-2 sm:grid-cols-2">
        <div>
          <dt class="text-sm font-medium text-gray-500">Asked At</dt>
          <dd class="mt-1 text-sm text-gray-900">
            {Calendar.strftime(@entry.inserted_at, "%B %d, %Y at %I:%M %p")}
          </dd>
        </div>

        <%= if @entry.user do %>
          <div>
            <dt class="text-sm font-medium text-gray-500">User</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {@entry.user.email || "Anon"}
            </dd>
          </div>
        <% end %>
      </div>

      <%= if @entry.source do %>
        <div class="mt-4">
          <dt class="text-sm font-medium text-gray-500">Source</dt>
          <dd class="mt-1 text-sm text-gray-900 break-words">
            {@entry.source}
          </dd>
        </div>
      <% end %>

      <%= if not @entry.is_successful do %>
        <div class="mt-4 p-3 bg-red-100 rounded">
          <dt class="text-sm font-medium text-red-600">Errors</dt>
          <dd class="mt-1 text-sm text-red-900">
            {@entry.errors}
          </dd>
        </div>
      <% end %>
    </div>
    """
  end
end

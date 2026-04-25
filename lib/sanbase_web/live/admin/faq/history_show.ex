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
            class="link link-primary text-sm mb-2 inline-block"
          >
            ← Back to History
          </.link>
          <h1 class="text-3xl font-bold">{@entry.question}</h1>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-300 shadow overflow-hidden">
        <div class="px-6 py-4 border-b border-base-300">
          <h3 class="text-lg font-medium">Answer</h3>
        </div>
        <div class="px-6 py-6">
          <div class="prose max-w-none">
            {Phoenix.HTML.raw(@answer_html)}
          </div>
        </div>
      </div>

      <div class="mt-6 grid grid-cols-1 gap-x-4 gap-y-2 sm:grid-cols-2">
        <div>
          <dt class="text-sm font-medium text-base-content/60">Asked At</dt>
          <dd class="mt-1 text-sm">
            {Calendar.strftime(@entry.inserted_at, "%B %d, %Y at %I:%M %p")}
          </dd>
        </div>

        <%= if @entry.user do %>
          <div>
            <dt class="text-sm font-medium text-base-content/60">User</dt>
            <dd class="mt-1 text-sm">
              {@entry.user.email || "Anon"}
            </dd>
          </div>
        <% end %>
      </div>

      <%= if @entry.source do %>
        <div class="mt-4">
          <dt class="text-sm font-medium text-base-content/60">Source</dt>
          <dd class="mt-1 text-sm break-words">
            {@entry.source}
          </dd>
        </div>
      <% end %>

      <%= if not @entry.is_successful do %>
        <div class="alert alert-error mt-4">
          <div>
            <dt class="text-sm font-medium">Errors</dt>
            <dd class="mt-1 text-sm">
              {@entry.errors}
            </dd>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

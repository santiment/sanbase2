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

        <div :if={@entry.user}>
          <dt class="text-sm font-medium text-base-content/60">User</dt>
          <dd class="mt-1 text-sm">
            {@entry.user.email || "Anon"}
          </dd>
        </div>

        <div :if={@entry.model}>
          <dt class="text-sm font-medium text-base-content/60">Model</dt>
          <dd class="mt-1 text-sm">
            {@entry.model}
          </dd>
        </div>
      </div>

      <div :if={@entry.source} class="mt-4">
        <dt class="text-sm font-medium text-base-content/60">Source</dt>
        <dd class="mt-1 text-sm break-words">
          {@entry.source}
        </dd>
      </div>

      <div :if={@entry.query_plan} class="mt-4">
        <dt class="text-sm font-medium text-base-content/60">Query plan</dt>
        <dd class="mt-1 text-sm">
          <span :if={@entry.query_plan["has_topic"]} class="font-mono">
            search: {@entry.query_plan["semantic_query"]}
          </span>
          <span :if={!@entry.query_plan["has_topic"]} class="badge badge-sm badge-info">
            browse newest
          </span>
          <span class={"ml-2 badge badge-sm #{if @entry.query_plan["sort"] == "recency", do: "badge-success", else: "badge-ghost"}"}>
            {@entry.query_plan["sort"]}
          </span>
          <span
            :if={@entry.query_plan["date_from"] || @entry.query_plan["date_to"]}
            class="ml-2 text-base-content/60"
          >
            {@entry.query_plan["date_from"] || "—"} → {@entry.query_plan["date_to"] || "—"}
          </span>
        </dd>
      </div>

      <div :if={not @entry.is_successful} class="alert alert-error mt-4">
        <div>
          <dt class="text-sm font-medium">Errors</dt>
          <dd class="mt-1 text-sm">
            {@entry.errors}
          </dd>
        </div>
      </div>
    </div>
    """
  end
end

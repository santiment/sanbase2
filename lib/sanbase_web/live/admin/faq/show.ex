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

  def handle_event("publish", _params, socket) do
    %{entry: seen, current_user: reviewer} = socket.assigns

    {kind, message} =
      case Faq.publish(seen, reviewer) do
        {:ok, _entry} ->
          {:info, "FAQ entry published. It is now used in answers."}

        {:error, :changed} ->
          {:error,
           "This draft was edited after you opened it. Review the current version below " <>
             "and publish again."}

        {:error, :not_a_draft} ->
          {:error, "This entry is no longer a draft: it was already published or rejected."}
      end

    {:noreply,
     socket
     |> assign(:entry, Faq.get_entry!(seen.id))
     |> put_flash(kind, message)}
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
            class="link link-primary text-sm mb-2 inline-block"
          >
            ← Back to FAQ List
          </.link>
          <h1 class="text-3xl font-bold">{@entry.question}</h1>
        </div>
        <div class="flex items-center space-x-3">
          <button
            :if={@entry.status == :draft and not @entry.is_deleted}
            id="faq-publish"
            phx-click="publish"
            phx-disable-with="Publishing..."
            data-confirm="Publish this entry? It will be used in answers right away."
            class="btn btn-success"
          >
            <.icon name="hero-check" class="size-4" /> Publish
          </button>
          <.link navigate={~p"/admin/faq/#{@entry.id}/edit"} class="btn btn-warning">
            Edit
          </.link>
          <button
            id="faq-delete"
            phx-click="delete"
            data-confirm={
              if @entry.status == :draft,
                do: "Reject and delete this draft?",
                else: "Are you sure you want to delete this FAQ entry?"
            }
            class="btn btn-error"
          >
            {if @entry.status == :draft, do: "Reject", else: "Delete"}
          </button>
        </div>
      </div>

      <div
        :if={@entry.status == :draft}
        id="faq-draft-banner"
        class="mb-6 flex gap-3 rounded-box border border-warning/40 bg-warning/10 p-4"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning mt-0.5" />
        <div class="text-sm">
          <p class="font-medium">Draft — not used in answers until published</p>
          <p class="mt-1 text-base-content/70">
            Created {if @entry.origin == :mcp,
              do: "by Claude through the knowledge MCP",
              else: "in the admin panel"}
            <span :if={@entry.created_by}>
              on behalf of <span class="font-medium">{@entry.created_by.email}</span>
            </span>. Check the answer for accuracy before publishing.
          </p>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-300 shadow overflow-hidden">
        <div class="px-6 py-4 border-b border-base-300">
          <h3 class="text-lg font-medium">Answer</h3>
        </div>
        <div class="px-6 py-6">
          <div class="prose max-w-none">
            {Phoenix.HTML.raw(@entry.answer_html)}
          </div>
        </div>
      </div>

      <div
        :if={@entry.internal_notes not in [nil, ""]}
        id="faq-internal-notes"
        class="mt-6 rounded-box border border-base-300 p-4"
      >
        <h3 class="text-sm font-medium text-base-content/60">
          Internal notes (never shown to users)
        </h3>
        <p class="mt-2 text-sm whitespace-pre-wrap">{@entry.internal_notes}</p>
      </div>

      <div class="mt-6 bg-base-200 rounded-box p-4">
        <dl class="grid grid-cols-1 gap-x-4 gap-y-4 sm:grid-cols-2">
          <div :if={@entry.source_url}>
            <dt class="text-sm font-medium text-base-content/60">Source URL</dt>
            <dd class="mt-1 text-sm">
              <a href={@entry.source_url} target="_blank" class="link link-primary break-all">
                {@entry.source_url}
              </a>
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-base-content/60">Created</dt>
            <dd class="mt-1 text-sm">
              {Calendar.strftime(@entry.inserted_at, "%B %d, %Y at %I:%M %p UTC")}
            </dd>
          </div>
          <div :if={@entry.reviewed_at}>
            <dt class="text-sm font-medium text-base-content/60">Reviewed</dt>
            <dd class="mt-1 text-sm">
              {Calendar.strftime(@entry.reviewed_at, "%B %d, %Y at %I:%M %p UTC")}
              <span :if={@entry.reviewed_by}>by {@entry.reviewed_by.email}</span>
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-base-content/60">Last Updated</dt>
            <dd class="mt-1 text-sm">
              {Calendar.strftime(@entry.updated_at, "%B %d, %Y at %I:%M %p UTC")}
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end
end

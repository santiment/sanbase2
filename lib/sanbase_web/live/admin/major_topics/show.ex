defmodule SanbaseWeb.Admin.MajorTopicsLive.Show do
  use SanbaseWeb, :live_view

  alias Sanbase.MajorTopics

  def mount(%{"id" => id}, _session, socket) do
    batch = MajorTopics.get_batch!(id)

    {:ok,
     socket
     |> assign(
       :page_title,
       "Batch #{Date.to_iso8601(batch.interval_start)} → #{Date.to_iso8601(batch.interval_end)}"
     )
     |> assign(:current_user, socket.assigns[:current_user])
     |> assign_batch(batch)}
  end

  defp assign_batch(socket, batch) do
    active_count = Enum.count(batch.topics, fn t -> !t.is_removed end)

    socket
    |> assign(:batch, batch)
    |> assign(:active_count, active_count)
    |> assign(:editing_id, nil)
    |> assign_new(:viewing_id, fn -> nil end)
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_id, String.to_integer(id))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  def handle_event("view_description", %{"id" => id}, socket) do
    {:noreply, assign(socket, :viewing_id, String.to_integer(id))}
  end

  def handle_event("close_description", _params, socket) do
    {:noreply, assign(socket, :viewing_id, nil)}
  end

  def handle_event("save", %{"topic_id" => id, "label" => label}, socket) do
    topic = MajorTopics.get_topic!(id)

    case MajorTopics.update_topic(topic, %{label: label}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Label updated")
         |> assign_batch(MajorTopics.get_batch!(socket.assigns.batch.id))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Update failed: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    topic = MajorTopics.get_topic!(id)
    {:ok, _} = MajorTopics.mark_topic_removed(topic)

    {:noreply,
     socket
     |> put_flash(:info, "Topic removed")
     |> assign_batch(MajorTopics.get_batch!(socket.assigns.batch.id))}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    topic = MajorTopics.get_topic!(id)
    {:ok, _} = MajorTopics.restore_topic(topic)

    {:noreply,
     socket
     |> put_flash(:info, "Topic restored")
     |> assign_batch(MajorTopics.get_batch!(socket.assigns.batch.id))}
  end

  def handle_event("publish", _params, socket) do
    user_id = current_user_id(socket)

    case MajorTopics.publish_batch(socket.assigns.batch, user_id) do
      {:ok, _batch} ->
        {:noreply,
         socket
         |> put_flash(:info, "Batch published")
         |> assign_batch(MajorTopics.get_batch!(socket.assigns.batch.id))}

      {:error, :already_published} ->
        {:noreply, put_flash(socket, :error, "Batch is already published")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Publish failed: #{inspect(changeset.errors)}")}
    end
  end

  defp current_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl">
      <div class="mb-4">
        <.link navigate={~p"/admin/major_topics"} class="link text-sm">
          ← Back to batches
        </.link>
      </div>

      <div class="flex items-start justify-between mb-6">
        <div>
          <h1 class="text-3xl font-bold">
            Major Topics Batch {Date.to_iso8601(@batch.interval_start)} → {Date.to_iso8601(
              @batch.interval_end
            )}
          </h1>
          <div class="mt-2 text-sm text-base-content/70 space-x-3 font-mono">
            <span>id: {@batch.id}</span>
            <span>•</span>
            <span>source: {@batch.source}</span>
            <span>•</span>
            <span>version: {@batch.version}</span>
            <span>•</span>
            <span class={["badge badge-sm", state_badge(@batch.state)]}>{@batch.state}</span>
            <span>•</span>
            <span>{@active_count} active / {length(@batch.topics)} total</span>
          </div>
          <div :if={@batch.published_at} class="mt-1 text-xs text-base-content/60">
            Published {Calendar.strftime(@batch.published_at, "%Y-%m-%d %H:%M UTC")}
          </div>
        </div>

        <div>
          <button
            :if={@batch.state == "draft" and @active_count > 0}
            phx-click="publish"
            data-confirm="Publish this batch? It will become the latest live batch on the public GraphQL API."
            class="btn btn-primary"
          >
            Publish batch
          </button>
          <span :if={@batch.state == "published"} class="badge badge-success">
            Live on GraphQL
          </span>
        </div>
      </div>

      <div class="rounded-box border border-base-300 overflow-hidden">
        <table class="table">
          <thead>
            <tr>
              <th class="w-12">#</th>
              <th class="w-1/4">Label</th>
              <th>Top words</th>
              <th>Description</th>
              <th class="w-20 text-right">Points</th>
              <th class="w-32 text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={topic <- @batch.topics}
              class={topic.is_removed && "opacity-40 line-through"}
            >
              <td class="text-xs text-base-content/60">{topic.position}</td>
              <td>
                <form
                  :if={@editing_id == topic.id}
                  phx-submit="save"
                  class="flex items-center gap-2"
                >
                  <input type="hidden" name="topic_id" value={topic.id} />
                  <input
                    type="text"
                    name="label"
                    value={topic.label}
                    class="input input-sm input-bordered w-full"
                    autofocus
                  />
                  <button type="submit" class="btn btn-sm btn-primary">Save</button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="btn btn-sm btn-ghost"
                  >
                    Cancel
                  </button>
                </form>
                <div :if={@editing_id != topic.id} class="flex items-center gap-2">
                  <span class="font-medium">{topic.label}</span>
                  <span
                    :if={topic.label != topic.original_label}
                    class="badge badge-xs badge-info"
                    title={"Original: #{topic.original_label}"}
                  >
                    edited
                  </span>
                </div>
              </td>
              <td class="font-mono text-xs">{topic.top_words}</td>
              <td class="text-xs text-base-content/80">
                <button
                  type="button"
                  phx-click="view_description"
                  phx-value-id={topic.id}
                  class="text-left line-clamp-3 hover:text-primary cursor-pointer"
                  title="Click to view full description"
                >
                  {topic.description}
                </button>
              </td>
              <td class="text-right text-xs">{length(topic.values)}</td>
              <td class="text-right whitespace-nowrap">
                <button
                  :if={@editing_id != topic.id and @batch.state == "draft"}
                  phx-click="edit"
                  phx-value-id={topic.id}
                  class="link link-primary text-sm"
                >
                  Edit
                </button>
                <button
                  :if={@batch.state == "draft" and !topic.is_removed}
                  phx-click="remove"
                  phx-value-id={topic.id}
                  data-confirm="Remove this topic from the batch?"
                  class="link text-error text-sm ml-2"
                >
                  Remove
                </button>
                <button
                  :if={@batch.state == "draft" and topic.is_removed}
                  phx-click="restore"
                  phx-value-id={topic.id}
                  class="link text-warning text-sm ml-2"
                >
                  Restore
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        :if={@viewing_id}
        class="fixed inset-0 z-50 flex items-center justify-center"
        phx-window-keydown="close_description"
        phx-key="escape"
      >
        <div class="absolute inset-0 bg-black/50" phx-click="close_description"></div>
        <% topic = Enum.find(@batch.topics, &(&1.id == @viewing_id)) %>
        <div class="relative bg-base-100 rounded-box shadow-xl max-w-2xl w-full mx-4 max-h-[80vh] overflow-hidden flex flex-col">
          <div class="px-6 py-4 border-b border-base-300 flex items-start justify-between gap-4">
            <div>
              <h2 class="text-lg font-bold">{topic && topic.label}</h2>
              <p :if={topic} class="text-xs text-base-content/60 mt-1 font-mono">
                {topic.top_words}
              </p>
            </div>
            <button
              type="button"
              phx-click="close_description"
              class="btn btn-sm btn-ghost btn-circle"
              aria-label="Close"
            >
              ✕
            </button>
          </div>
          <div class="px-6 py-4 overflow-y-auto whitespace-pre-wrap text-sm leading-relaxed">
            {topic && topic.description}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp state_badge("published"), do: "badge-success"
  defp state_badge("draft"), do: "badge-warning"
  defp state_badge(_), do: "badge-neutral"
end

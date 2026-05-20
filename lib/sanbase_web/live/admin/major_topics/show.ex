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

  @highlight_top_red 10
  @highlight_top_yellow 20

  defp assign_batch(socket, batch) do
    active_count = Enum.count(batch.topics, fn t -> !t.is_removed end)

    active = Enum.reject(batch.topics, & &1.is_removed)

    red_ids =
      active
      |> Enum.take(@highlight_top_red)
      |> MapSet.new(& &1.id)

    yellow_ids =
      active
      |> Enum.slice(@highlight_top_red, @highlight_top_yellow - @highlight_top_red)
      |> MapSet.new(& &1.id)

    socket
    |> assign(:batch, batch)
    |> assign(:active_count, active_count)
    |> assign(:red_ids, red_ids)
    |> assign(:yellow_ids, yellow_ids)
    |> assign(:editing_id, nil)
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case find_topic_in_batch(socket, id) do
      nil -> {:noreply, socket}
      topic -> {:noreply, assign(socket, :editing_id, topic.id)}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  def handle_event("save", %{"topic_id" => id, "label" => label}, socket) do
    with topic when not is_nil(topic) <- find_topic_in_batch(socket, id),
         {:ok, _} <- MajorTopics.update_topic(topic, %{label: label}) do
      {:noreply,
       socket
       |> put_flash(:info, "Label updated")
       |> assign_batch(MajorTopics.get_batch!(socket.assigns.batch.id))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Topic not found in this batch")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Update failed: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    with topic when not is_nil(topic) <- find_topic_in_batch(socket, id),
         {:ok, _} <- MajorTopics.mark_topic_removed(topic) do
      {:noreply,
       socket
       |> put_flash(:info, "Topic removed")
       |> assign_batch(MajorTopics.get_batch!(socket.assigns.batch.id))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Topic not found in this batch")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Remove failed: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    with topic when not is_nil(topic) <- find_topic_in_batch(socket, id),
         {:ok, _} <- MajorTopics.restore_topic(topic) do
      {:noreply,
       socket
       |> put_flash(:info, "Topic restored")
       |> assign_batch(MajorTopics.get_batch!(socket.assigns.batch.id))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Topic not found in this batch")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Restore failed: #{inspect(changeset.errors)}")}
    end
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

  defp find_topic_in_batch(socket, id) do
    Enum.find(socket.assigns.batch.topics, fn t -> to_string(t.id) == to_string(id) end)
  end

  defp current_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-screen-2xl">
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
        <table class="table w-full">
          <thead>
            <tr>
              <th class="w-12">#</th>
              <th class="w-56">Label</th>
              <th class="w-28">Top words</th>
              <th>Description</th>
              <th class="w-16 text-right">Points</th>
              <th class="w-28 text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={topic <- @batch.topics}
              class={[topic.is_removed && "opacity-40 line-through"]}
              style={row_highlight_style(topic, @red_ids, @yellow_ids)}
            >
              <td class="text-xs text-base-content/60 align-top">{topic.position}</td>
              <td class="align-top">
                <div class="flex items-start gap-1 flex-wrap">
                  <span class="font-medium text-sm">{topic.label}</span>
                  <span
                    :if={topic.label != topic.original_label}
                    class="badge badge-xs badge-info"
                    title={"Original: #{topic.original_label}"}
                  >
                    edited
                  </span>
                </div>
              </td>
              <td class="font-mono text-[11px] align-top">
                <div class="flex flex-col gap-0.5 leading-tight">
                  <span :for={word <- String.split(topic.top_words || "", ",", trim: true)}>
                    {word}
                  </span>
                </div>
              </td>
              <td class="text-[11px] leading-snug text-base-content/80 whitespace-pre-wrap align-top">
                {topic.description}
              </td>
              <td class="text-right text-xs align-top">{length(topic.values)}</td>
              <td class="text-right whitespace-nowrap align-top">
                <button
                  :if={@batch.state == "draft"}
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
        :if={@editing_id}
        class="fixed inset-0 z-50 flex items-center justify-center"
        phx-window-keydown="cancel_edit"
        phx-key="escape"
      >
        <div class="absolute inset-0 bg-black/50" phx-click="cancel_edit"></div>
        <% editing_topic = Enum.find(@batch.topics, &(&1.id == @editing_id)) %>
        <div
          :if={editing_topic}
          class="relative bg-base-100 rounded-box shadow-xl max-w-2xl w-full mx-4 flex flex-col"
        >
          <div class="px-6 py-4 border-b border-base-300 flex items-start justify-between gap-4">
            <div>
              <h2 class="text-lg font-bold">Edit label</h2>
              <p class="text-xs text-base-content/60 mt-1">
                Original: <span class="font-mono">{editing_topic.original_label}</span>
              </p>
            </div>
            <button
              type="button"
              phx-click="cancel_edit"
              class="btn btn-sm btn-ghost btn-circle"
              aria-label="Close"
            >
              ✕
            </button>
          </div>
          <form phx-submit="save" class="px-6 py-4 flex flex-col gap-3">
            <input type="hidden" name="topic_id" value={editing_topic.id} />
            <input
              type="text"
              name="label"
              value={editing_topic.label}
              class="input input-bordered w-full"
              autofocus
            />
            <div class="flex items-center justify-end gap-2">
              <button type="button" phx-click="cancel_edit" class="btn btn-ghost">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp state_badge("published"), do: "badge-success"
  defp state_badge("draft"), do: "badge-warning"
  defp state_badge(_), do: "badge-neutral"

  defp row_highlight_style(topic, red_ids, yellow_ids) do
    cond do
      MapSet.member?(red_ids, topic.id) -> "background-color: #fecaca;"
      MapSet.member?(yellow_ids, topic.id) -> "background-color: #fef08a;"
      true -> nil
    end
  end
end

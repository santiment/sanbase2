defmodule SanbaseWeb.Admin.FaqLive.Form do
  use SanbaseWeb, :live_view

  alias Sanbase.Knowledge.Faq
  alias Sanbase.Knowledge.FaqEntry

  def mount(params, _session, socket) do
    action = if Map.has_key?(params, "id"), do: :edit, else: :new

    {entry, tags} =
      case params do
        %{"id" => id} ->
          entry = Faq.get_entry!(id)
          tags = entry.tags |> Enum.map(& &1.name)
          {entry, tags}

        _ ->
          {%FaqEntry{tags: []}, []}
      end

    changeset = Faq.change_entry(entry)

    socket =
      socket
      |> assign(:entry, entry)
      |> assign(:changeset, changeset)
      |> assign(:form, to_form(changeset))
      |> assign(:action, action)
      |> assign(:page_title, "New FAQ Entry")
      |> assign(:tags, tags)
      |> assign(:similar_entries, [])

    {:ok, socket}
  end

  def handle_event("check_similar", %{"question" => question}, socket) do
    case Faq.find_most_similar_faqs(question || "", 5) do
      {:ok, entries} when entries != [] ->
        socket = socket |> assign(:similar_entries, entries)
        {:noreply, socket}

      _ ->
        socket = socket |> assign(:similar_entries, [])
        {:noreply, socket}
    end
  end

  def handle_event("validate", %{"faq_entry" => faq_entry_params}, socket) do
    changeset =
      socket.assigns.entry
      |> Faq.change_entry(faq_entry_params |> Map.put("tags", socket.assigns.tags))
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:form, to_form(changeset))
      |> assign(:similar_entries, [])

    {:noreply, socket}
  end

  def handle_event("save", %{"faq_entry" => faq_entry_params}, socket) do
    save_entry(socket, socket.assigns.action, faq_entry_params)
  end

  def handle_event("render_markdown", %{"markdown" => markdown}, socket) do
    html =
      case Earmark.as_html(markdown || "") do
        {:ok, html} -> HtmlSanitizeEx.html5(html)
        {:ok, html, _} -> HtmlSanitizeEx.html5(html)
        {:error, html, _} -> HtmlSanitizeEx.html5(html)
        {:error, _} -> "<p class=\"text-gray-500\">Invalid markdown</p>"
      end

    {:reply, %{html: html}, socket}
  end

  defp save_entry(socket, :edit, faq_entry_params) do
    case Faq.update_entry(socket.assigns.entry, faq_entry_params) do
      {:ok, entry} ->
        socket =
          socket
          |> put_flash(:info, "FAQ entry updated successfully")
          |> push_navigate(to: ~p"/admin/faq/#{entry.id}")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:changeset, changeset)
          |> assign(:form, to_form(changeset))

        {:noreply, socket}
    end
  end

  defp save_entry(socket, :new, faq_entry_params) do
    case Faq.create_entry(faq_entry_params) do
      {:ok, entry} ->
        socket =
          socket
          |> put_flash(:info, "FAQ entry created successfully")
          |> push_navigate(to: ~p"/admin/faq/#{entry.id}")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:changeset, changeset)
          |> assign(:form, to_form(changeset))

        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="mb-6">
        <.link
          navigate={~p"/admin/faq"}
          class="text-blue-600 hover:text-blue-800 font-medium text-sm mb-2 inline-block"
        >
          ← Back to FAQ List
        </.link>
        <h1 class="text-3xl font-bold text-gray-900">{@page_title}</h1>
      </div>

      <.form for={@form} id="faq-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <div>
          <.input
            field={@form[:question]}
            type="textarea"
            label="Question"
            placeholder="Enter the FAQ question..."
            rows="2"
            autofocus
            class="w-full text-xl font-semibold"
          />
        </div>
        <button
          :if={is_binary(@form[:question].value) and @form[:question].value != ""}
          phx-click="check_similar"
          phx-disable-with="Checking for similarity..."
          phx-value-question={@form[:question].value}
          class="bg-white hover:bg-gray-100 text-gray-800 font-semibold py-2 px-4 border border-gray-400 rounded text-base"
        >
          Check for similar questions
        </button>
        <div :if={@similar_entries != []}>
          <h3 class="font-medium text-gray-700 mb-2">Most Similar FAQ Entries</h3>
          <div :for={entry <- @similar_entries}>
            <span class="text-gray-800 mb-2">
              {entry.similarity |> Float.round(2)} | {entry.question}
            </span>
            <.link
              navigate={~p"/admin/faq/#{entry.id}"}
              class="text-blue-600 hover:text-blue-800 font-medium text-sm"
            >
              Link
            </.link>
          </div>
        </div>

        <div>
          <.input
            field={@form[:source_url]}
            type="url"
            label="Source URL (optional)"
            placeholder="https://discord.com/channels/..."
            class="w-full"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">
            Answer (Markdown)
          </label>
          <div
            id="easymde-container"
            phx-hook="EasyMDEEditor"
            phx-update="ignore"
            data-target-input="faq_entry_answer_markdown"
            class="w-full"
          >
            <textarea id="easymde-editor" class="w-full" style="min-height: 400px;"></textarea>
          </div>
          <input
            type="hidden"
            id="faq_entry_answer_markdown"
            class=" text-grey-900"
            name={@form[:answer_markdown].name}
            value={@form[:answer_markdown].value || ""}
          />
          <%= if @changeset.errors[:answer_markdown] do %>
            <div class="mt-1 text-sm text-red-600">
              {elem(@changeset.errors[:answer_markdown], 0)}
            </div>
          <% end %>
        </div>

        <.tags form={@form} tags={@tags} />
        <div class="flex items-center justify-end space-x-3">
          <.link
            navigate={if @action == :edit, do: ~p"/admin/faq/#{@entry.id}", else: ~p"/admin/faq"}
            class="px-4 py-2 text-gray-700 bg-gray-200 hover:bg-gray-300 rounded-lg font-medium transition-colors"
          >
            Cancel
          </.link>
          <button
            type="submit"
            class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
          >
            {if @action == :edit, do: "Update", else: "Create"} FAQ Entry
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp tags(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">Tags</label>
      <div class="flex gap-6 flex-wrap">
        <label
          :for={tag <- ["code", "subscription", "api", "metrics", "payment", "sanbase"]}
          class="inline-flex items-center gap-2"
        >
          <input
            type="checkbox"
            name="faq_entry[tags][]"
            value={tag}
            checked={Enum.member?(@tags, tag)}
          /> <span class="text-sm">{tag}</span>
        </label>
      </div>
    </div>
    """
  end
end

defmodule SanbaseWeb.Admin.FaqLive.Form do
  use SanbaseWeb, :live_view

  alias Sanbase.Knowledge.Faq
  alias Sanbase.Knowledge.FaqEntry

  def mount(%{"id" => id}, _session, socket) do
    entry = Faq.get_entry!(id)
    changeset = Faq.change_entry(entry)

    socket =
      socket
      |> assign(:entry, entry)
      |> assign(:changeset, changeset)
      |> assign(:form, to_form(changeset))
      |> assign(:action, :edit)
      |> assign(:page_title, "Edit FAQ Entry")
      |> assign(:preview_html, entry.answer_html)

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    entry = %FaqEntry{}
    changeset = Faq.change_entry(entry)

    socket =
      socket
      |> assign(:entry, entry)
      |> assign(:changeset, changeset)
      |> assign(:form, to_form(changeset))
      |> assign(:action, :new)
      |> assign(:page_title, "New FAQ Entry")
      |> assign(:preview_html, "")

    {:ok, socket}
  end

  def handle_event("validate", %{"faq_entry" => faq_entry_params}, socket) do
    changeset =
      socket.assigns.entry
      |> Faq.change_entry(faq_entry_params)
      |> Map.put(:action, :validate)

    preview_html = generate_preview_html(faq_entry_params["answer_markdown"] || "")

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:form, to_form(changeset))
      |> assign(:preview_html, preview_html)

    {:noreply, socket}
  end

  def handle_event("save", %{"faq_entry" => faq_entry_params}, socket) do
    save_entry(socket, socket.assigns.action, faq_entry_params)
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

  defp generate_preview_html(""), do: ""

  defp generate_preview_html(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html} -> HtmlSanitizeEx.html5(html)
      {:ok, html, _messages} -> HtmlSanitizeEx.html5(html)
      {:error, html, _messages} -> HtmlSanitizeEx.html5(html)
      {:error, _reason} -> "<p class=\"text-red-600\">Invalid markdown</p>"
    end
  end

  defp generate_preview_html(_), do: ""

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
            type="text"
            label="Question"
            placeholder="Enter the FAQ question..."
            class="w-full"
          />
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

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Answer (Markdown)
            </label>
            <div
              id="monaco-editor"
              phx-hook="MonacoEditor"
              phx-update="ignore"
              data-target-input="faq_entry_answer_markdown"
              class="border-2 border-gray-300 rounded-xl shadow-sm hover:border-blue-400 focus-within:border-blue-500 focus-within:ring-2 focus-within:ring-blue-200 transition-all duration-200"
              style="height: 600px;"
            >
            </div>
            <input
              type="hidden"
              id="faq_entry_answer_markdown"
              name={@form[:answer_markdown].name}
              value={@form[:answer_markdown].value || ""}
            />
            <%= if @changeset.errors[:answer_markdown] do %>
              <div class="mt-1 text-sm text-red-600">
                {elem(@changeset.errors[:answer_markdown], 0)}
              </div>
            <% end %>
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Preview
            </label>
            <div
              class="border-2 border-gray-200 rounded-xl p-6 bg-gray-50 shadow-sm"
              style="height: 600px; overflow-y: auto;"
            >
              <%= if @preview_html == "" do %>
                <p class="text-gray-500 italic">Preview will appear here as you type...</p>
              <% else %>
                <div class="prose max-w-none">
                  {Phoenix.HTML.raw(@preview_html)}
                </div>
              <% end %>
            </div>
          </div>
        </div>

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
end

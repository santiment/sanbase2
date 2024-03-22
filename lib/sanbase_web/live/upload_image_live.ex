defmodule SanbaseWeb.UploadImageLive do
  use SanbaseWeb, :live_view

  alias SanbaseWeb.EcosystemComponents
  alias SanbaseWeb.Admin.UserSubmissionAdminComponents

  @impl true
  def mount(_params, _session, socket) do
    socket =
      allow_upload(
        socket,
        :images,
        accept: ~w(.png .jpg .jpeg),
        max_entries: 1,
        max_file_size: 10_000_000
      )
      |> assign(:form, to_form(%{}))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-gray-100 mx-auto max-w-3xl p-6 rounded-xl shadow-sm min-h-96">
      <.form
        for={@form}
        phx-submit="save"
        phx-change="validate"
        class="bg-white px-8 py-6 mb-6 shadow rounded-lg mx-auto w-full max-w-xl"
      >
        <.input
          field={@form[:name]}
          placeholder="Name"
          class="mb-4 appearance-none block w-full px-3 py-2 border border-slate-300 rounded-md transition duration-150 ease-in-out;"
        />

        <div class="my-4 text-slate-600 text-sm">
          Add one file max <%= trunc(@uploads.images.max_file_size / 1_000_000) %> MB in size
        </div>
        <div
          class="flex items-baseline justify-center space-x-1 my-2 p-4 border-2 border-dashed border-slate-300 rounded-md text-center text-slate-600"
          phx-drop-target={@uploads.images.ref}
        >
          <div>
            <.icon name="hero-document-plus" class="size-12 text-gray-400" />
            <div>
              <label
                for={@uploads.images.ref}
                class="cursor-pointer font-medium text-indigo-600 hover:text-indigo-500"
              >
                <span>Upload a file</span>
                <.live_file_input upload={@uploads.images} class="sr-only" />
              </label>
              <span>or drag and drop here</span>
            </div>
            <p class="text-sm text-slate-500">
              <%= @uploads.images.max_entries %> images max,
              up to <%= trunc(@uploads.images.max_file_size / 1_000_000) %> MB each
            </p>
          </div>
        </div>

        <.error :for={error <- upload_errors(@uploads.images)}>
          <%= error_to_string(error) %>
        </.error>

        <div
          :for={entry <- @uploads.images.entries}
          class="my-6 flex items-center justify-start space-x-6"
          }
        >
          <.live_img_preview entry={entry} class="w-32" />
          <div class="w-full">
            <div class="text-left mb-2 text-xs font-semibold inline-block text-indigo-600">
              <%= entry.progress %>
            </div>
            <div class="flex h-2 overflow-hidden text-base bg-indigo-200 rounded-lg mb-4">
              <span class={"width: #{entry.progress}%"}></span>
            </div>

            <.error :for={error <- upload_errors(@uploads.images, entry)}>
              <%= error_to_string(error) %>
            </.error>
          </div>

          <a phx-click="cancel" phx-value-ref={entry.ref}>&times </a>
        </div>
        <.input
          type="checkbox"
          name="transform_logo"
          value="transform_to_logo"
          label="Transform to project logo format"
        />
        <.button
          phx-disable-with="Uploading..."
          class="mt-4 w-full py-2 px-4 border border-transparent font-medium rounded-md text-white bg-indigo-600 transition duration-150 ease-in-out hover:bg-indigo-500 active:bg-indigo-700 "
        >
          Upload
        </.button>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{}, socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{} = params, socket) do
    params |> dbg()

    [image_location] =
      consume_uploaded_entries(socket, :images, fn meta, entry ->
        dest = Path.join(["priv", "static", "uploads", "#{entry.uuid}-#{entry.client_name}"])

        File.mkdir_p!(Path.dirname(dest))
        File.cp!(meta.path, dest)

        url_path = static_path(socket, "/uploads/#{Path.basename(dest)}")

        {:ok, url_path}
      end)

    # params = Map.put(params, "photo_locations", photo_locations)

    # case Desks.create_desk(params) do
    #   {:ok, _desk} ->
    #     changeset = Desks.change_desk(%Desk{})
    #     {:noreply, assign_form(socket, changeset)}

    #   {:error, %Ecto.Changeset{} = changeset} ->
    #     {:noreply, assign_form(socket, changeset)}
    # end

    {:noreply, socket}
  end

  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp error_to_string(:too_large), do: "Gulp! File too large (max 10 MB)."
  defp error_to_string(:too_many_files), do: "Whoa, too many files."
  defp error_to_string(:not_accepted), do: "Sorry, that's not an acceptable file type."
end

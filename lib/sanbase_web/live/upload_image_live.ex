defmodule SanbaseWeb.UploadImageLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      allow_upload(
        socket,
        :images,
        accept: ~w(.png .jpg .jpeg .mp4),
        max_entries: 1,
        max_file_size: 10_000_000
      )
      |> assign(
        form: to_form(%{}),
        uploaded_file_url: nil
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-gray-100 mx-auto max-w-2xl p-6 rounded-xl shadow-sm min-h-96">
      <.form
        for={@form}
        phx-change="validate"
        phx-submit="save"
        class="bg-white rounded-lg mx-auto w-full"
      >
        <.input
          field={@form[:name]}
          placeholder="Name. Leave empty to use the name of the uploaded file"
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
          name="transform_to_logo"
          value="transform_to_logo"
          label="Transform to project logo format"
        />
        <p class="text-xs text-gray-500 ml-8">
          Logo images are resized to 64x64 and they are placed in the logo64 S3 scope, so the URL will start with logo64_ automatically.
          If you give a custom name to the logo image, there is no need to start with 'logo_'.
        </p>
        <.button
          phx-disable-with="Uploading..."
          class="mt-6 w-full !bg-violet-700 hover:!bg-violet-500"
        >
          Upload
        </.button>
      </.form>

      <div :if={@uploaded_file_url} class="break-words mt-6 text-sm text-gray-600">
        S3 URL of the uploaded file:
        <p class="underline text-blue-700"><%= @uploaded_file_url %></p>
      </div>
    </div>
    """
  end

  def handle_event("validate", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"name" => name} = params, socket) do
    image_locations =
      consume_uploaded_entries(socket, :images, fn meta, entry ->
        # Create a destination folder and file name
        filename = gen_filename(name, entry)

        dest = Temp.mkdir!("image_upload_live")
        filepath = Path.join(dest, filename)

        # If the transform_to_logo checkbox is checked, transform the image
        # to a 64x64 image, so it is consistent with the logos we have
        transform_to_logo = params["transform_to_logo"] == "true"
        {:ok, filepath} = maybe_resize_image(meta.path, filepath, transform_to_logo)
        # Upload the image to S3
        scope = if transform_to_logo, do: "logo64", else: "image"
        {:ok, s3_url} = Sanbase.FileStore.Image.upload_to_s3(filepath, scope)

        File.rm_rf!(dest)
        {:ok, s3_url}
      end)

    case image_locations do
      [image_location] ->
        socket =
          socket
          |> put_flash(:info, "Successfully uploaded file!")
          |> assign(:uploaded_file_url, image_location)

        {:noreply, socket}

      [] ->
        socket =
          socket
          |> put_flash(:error, "Attach an image before trying to upload")

        {:noreply, socket}
    end
  end

  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  def gen_filename(name, entry) do
    [_, extension] = String.split(entry.client_type, "/", parts: 2)
    client_name = String.trim_trailing(entry.client_name, Path.extname(entry.client_name))
    # Do not use Base64 as it contains '/', which can mess up the paths
    rand_part = :crypto.strong_rand_bytes(5) |> Base.encode32()

    # The client_name and name are both stripepd of extensions
    name = if name == "", do: client_name, else: name

    name <> "_" <> rand_part <> "." <> extension
  end

  defp maybe_resize_image(path, filepath, transform_to_logo) do
    if transform_to_logo do
      Mogrify.open(path)
      |> Mogrify.resize("64x64")
      |> Mogrify.custom("type", "PaletteAlpha")
      |> Mogrify.save(path: filepath)
    else
      File.cp!(path, filepath)
    end

    {:ok, filepath}
  end

  defp error_to_string(:too_large), do: "Gulp! File too large (max 10 MB)."
  defp error_to_string(:too_many_files), do: "Whoa, too many files."
  defp error_to_string(:not_accepted), do: "Sorry, that's not an acceptable file type."
end

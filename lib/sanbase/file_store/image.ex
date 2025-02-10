defmodule Sanbase.FileStore.Image do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  require Logger

  schema "images" do
    field(:url, :string)
    field(:name, :string)
    field(:notes, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = image, attrs) do
    image
    |> cast(attrs, [:url, :name, :notes])
    |> validate_required([:url, :name])
  end

  def all do
    Sanbase.Repo.all(from(i in __MODULE__, order_by: [desc: :id]))
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Sanbase.Repo.insert()
  end

  def resize_image(source_path, dest_path, filename, size) do
    dest_filepath = Path.join(dest_path, filename)

    source_path
    |> Mogrify.open()
    |> Mogrify.resize("#{size}x#{size}")
    |> Mogrify.custom("type", "PaletteAlpha")
    |> Mogrify.save(path: dest_filepath)

    {:ok, dest_filepath}
  rescue
    e ->
      error_msg = "Failed to resize an image with mogrify. Reason: #{Exception.message(e)}"
      Logger.info(error_msg)
      {:error, error_msg}
  end

  def upload_to_s3(filepath, scope) do
    # The arguments are {file, scope}
    case Sanbase.FileStore.store({filepath, scope}) do
      {:ok, filename} ->
        Logger.info("Successfully uploaded an image from #{filepath} to: #{filename}")
        url = Sanbase.FileStore.url({filename, scope})
        # Create a record in the DB to keep track of the uploaded files
        _ =
          create(%{
            name: Path.basename(filepath),
            url: url
          })

        {:ok, url}

      {:error, error} ->
        error_msg = "Failed uploading logo: #{filepath}. Error message: #{inspect(error)}"
        Logger.error(error_msg)

        {:error, error_msg}
    end
  end
end

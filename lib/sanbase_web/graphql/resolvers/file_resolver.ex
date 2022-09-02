defmodule SanbaseWeb.Graphql.Resolvers.FileResolver do
  require Logger

  alias Sanbase.FileStore
  alias Sanbase.Insight.PostImage
  alias Sanbase.Utils.FileHash

  @doc ~s"""
    Receives a list of `%Plug.Upload{}` representing the images and uploads them.
    The files are first uploaded to an AWS S3 bucket and then then the image url,
    the content hash and used hash algorithm are stored in postgres.
  """
  def upload_image(_root, %{images: images}, _resolution) do
    # In S3 there are no folders so the file name just contains some random text
    # and a slash in it. Locally (in test and dev mode) the files are treated as if
    # they are located in a folder called `scope`

    image_data =
      images
      |> Enum.map(fn %{filename: file_name} = arg ->
        # Prepend the timestamp in milliseconds to the name to avoid name collision
        # when uploading images with the same hash and name
        arg = %{arg | filename: milliseconds_str() <> "_" <> file_name}
        save_image_content(arg)
      end)

    :ok = save_image_meta_data(image_data)

    {:ok, image_data}
  end

  # Helper functions

  defp save_image_content(%Plug.Upload{filename: file_name} = arg) do
    with {:ok, content_hash} <- FileHash.calculate(arg.path),
         {:ok, file_name} <- FileStore.store({arg, content_hash}) do
      image_url = FileStore.url({file_name, content_hash})

      %{
        file_name: file_name,
        image_url: image_url,
        content_hash: content_hash,
        hash_algorithm: FileHash.algorithm() |> Atom.to_string()
      }
    else
      {:error, error} ->
        %{
          file_name: file_name,
          error: error
        }
    end
  end

  # If the image map has error field != nil then it was not saved in S3/Local storage
  # and so the meta data in postgres should not be saved too. This error will be returned
  # in the query respose to propagate the error.
  defp save_image_meta_data(images) do
    images
    |> Enum.reject(&image_upload_error?/1)
    |> Enum.each(&PostImage.create!/1)
  end

  defp image_upload_error?(%{error: error}) when not is_nil(error), do: true
  defp image_upload_error?(_), do: false

  defp milliseconds_str() do
    DateTime.utc_now()
    |> DateTime.to_unix(:millisecond)
    |> Integer.to_string()
  end
end

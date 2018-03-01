defmodule SanbaseWeb.Graphql.Resolvers.FileResolver do
  require Logger

  alias Sanbase.FileStore
  alias Sanbase.Voting.PostImage

  @doc ~s"""
    Uploads the image to S3
  """
  def upload_image(_root, %{images: images}, _resolution) do
    # In S3 there are no folders so the file name just contains some random text
    # and a slash in it. Locally (in test and dev mode) the files are treaded as if
    # they are located in a folder called `scope`
    hash_algorithm = :sha256

    image_data =
      for arg <- images, into: [] do
        content_hash = image_content_hash!(arg, hash_algorithm)
        {:ok, file_name} = FileStore.store({arg, content_hash})
        image_url = FileStore.url({file_name, content_hash})

        %{
          file_name: file_name,
          image_url: image_url,
          content_hash: content_hash,
          hash_algorithm: hash_algorithm |> Atom.to_string()
        }
      end

    save_images_pg(image_data)

    {:ok, image_data}
  end

  # Helper functions

  defp image_content_hash!(%Plug.Upload{path: file_path}, hash_algorithm) do
    File.stream!(file_path, [], 8192)
    |> Enum.reduce(:crypto.hash_init(hash_algorithm), fn line, acc ->
      :crypto.hash_update(acc, line)
    end)
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()
  end

  defp save_images_pg(images) do
    images
    |> Enum.map(fn image ->
      %PostImage{}
      |> PostImage.changeset(Map.put(image, :post_id, nil))
      |> Sanbase.Repo.insert!()
    end)
  end
end

defmodule Sanbase.Voting.PostImage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Voting.Post
  alias __MODULE__

  schema "post_images" do
    belongs_to(:post, Post)

    field(:file_name, :string)
    field(:image_url, :string)
    field(:content_hash, :string)
    field(:hash_algorithm, :string)
  end

  def changeset(%PostImage{} = post_image, attrs \\ %{}) do
    post_image
    |> cast(attrs, [:post_id, :file_name, :image_url, :content_hash, :hash_algorithm])
    |> validate_required([:image_url, :content_hash, :hash_algorithm])
    |> update_change(:image_url, &String.downcase/1)
    |> unique_constraint(:image_url, name: :image_url_index)
  end
end

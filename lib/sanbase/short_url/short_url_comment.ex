defmodule Sanbase.ShortUrl.ShortUrlComment do
  @moduledoc ~s"""
  A mapping table connecting comments and short urls.

  This module is used to create, update, delete and fetch short url comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Comment
  alias Sanbase.ShortUrl

  schema "short_url_comments_mapping" do
    belongs_to(:comment, Comment)
    belongs_to(:short_url, ShortUrl)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:short_url_id, :comment_id])
    |> validate_required([:short_url_id, :comment_id])
    |> unique_constraint(:comment_id)
  end
end

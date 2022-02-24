defmodule Sanbase.Comment.ShortUrlComment do
  @moduledoc ~s"""
  A mapping table connecting comments and short urls.

  This module is used to create, update, delete and fetch short url comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "short_url_comments_mapping" do
    belongs_to(:comment, Sanbase.Comment)
    belongs_to(:short_url, Sanbase.ShortUrl)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:short_url_id, :comment_id])
    |> validate_required([:short_url_id, :comment_id])
    |> unique_constraint(:comment_id)
  end
end

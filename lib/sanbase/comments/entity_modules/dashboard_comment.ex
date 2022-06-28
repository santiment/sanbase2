defmodule Sanbase.Comment.DashboardComment do
  @moduledoc ~s"""
  A mapping table connecting comments and timeline events.

  This module is used to create, update, delete and fetch timeline events comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "dashboard_comments_mapping" do
    belongs_to(:comment, Sanbase.Comment)
    belongs_to(:dashboard, Sanbase.UserList)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:dashboard_id, :comment_id])
    |> validate_required([:dashboard_id, :comment_id])
    |> unique_constraint(:comment_id)
  end
end

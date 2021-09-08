defmodule Sanbase.Comment.ChartConfigurationComment do
  @moduledoc ~s"""
  A mapping table connecting comments and timeline events.

  This module is used to create, update, delete and fetch timeline events comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "chart_configuration_comments_mapping" do
    belongs_to(:comment, Sanbase.Comment)
    belongs_to(:chart_configuration, Sanbase.Chart.Configuration)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:chart_configuration_id, :comment_id])
    |> validate_required([:chart_configuration_id, :comment_id])
    |> unique_constraint(:comment_id)
  end
end

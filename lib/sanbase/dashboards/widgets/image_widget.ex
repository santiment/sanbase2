defmodule Sanbase.Dashboards.ImageWidget do
  @moduledoc ~s"""
  An embedded schema that represents a image widget.

  The image widgets are embedded in the "dashboards" table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: String.t(),
          url: String.t(),
          alt: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type image_widget_id :: String.t()
  @type image_widget_args :: %{
          required(:url) => String.t(),
          optional(:alt) => String.t()
        }

  embedded_schema do
    field(:url, :string)
    field(:alt, :string)

    timestamps()
  end

  @fields [:url, :alt]
  def changeset(%__MODULE__{} = widget, attrs) do
    widget
    |> cast(attrs, @fields)
    |> validate_required([:url])
  end
end

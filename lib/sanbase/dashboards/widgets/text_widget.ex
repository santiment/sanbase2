defmodule Sanbase.Dashboards.TextWidget do
  @moduledoc ~s"""
  An embedded schema that represents a text widget.

  The text widgets are embedded in the "dashboards" table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          description: String.t() | nil,
          body: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type text_widget_id :: String.t()
  @type text_widget_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:body) => String.t()
        }

  embedded_schema do
    field(:name, :string)
    field(:description, :string)
    field(:body, :string)

    timestamps()
  end

  @fields [:name, :description, :body]

  def changeset(%__MODULE__{} = widget, attrs) do
    cast(widget, attrs, @fields)
  end
end

defmodule Sanbase.Widget.ActiveWidget do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo

  schema "active_widgets" do
    field(:title, :string)
    field(:description, :string)
    field(:image_link, :string)
    field(:video_link, :string)
    field(:is_active, :boolean)

    timestamps()
  end

  def changeset(%__MODULE__{} = widget, attrs \\ %{}) do
    widget
    |> cast(attrs, [:title, :description, :image_link, :video_link, :is_active])
    |> validate_required([:title, :is_active])
  end

  def get_active_widgets() do
    from(
      widget in __MODULE__,
      where: widget.is_active == true
    )
    |> Repo.all()
  end
end

defmodule Sanbase.Insight.Category do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo

  schema "insight_categories" do
    field(:name, :string)
    field(:description, :string)

    many_to_many(:posts, Sanbase.Insight.Post,
      join_through: "insight_category_mapping",
      on_replace: :delete
    )

    timestamps()
  end

  def changeset(%__MODULE__{} = category, attrs \\ %{}) do
    category
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def all do
    Repo.all(__MODULE__)
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def by_names(names) when is_list(names) do
    from(c in __MODULE__, where: c.name in ^names)
    |> Repo.all()
  end
end

defmodule Sanbase.SocialData.PopularSearchTerm do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  schema "popular_search_terms" do
    field(:title, :string)
    field(:search_term, :string)
    field(:selector_type, :string)
    field(:datetime, :utc_datetime)
    field(:options, :map, default: %{})

    timestamps()
  end

  def changeset(%__MODULE__{} = term, attrs \\ %{}) do
    term
    |> cast(attrs, [:search_term, :selector_type, :datetime])
    |> validate_change(:selector_type, &validate_selector_type/2)
  end

  def get(from, to) do
    result =
      from(
        term in __MODULE__,
        where: term.datetime >= ^from and term.datetime < ^to
      )
      |> Sanbase.Repo.all()

    {:ok, result}
  end

  # Private functions

  defp validate_selector_type(:selector_type, selector_type) do
    case selector_type in ["text", "slug"] do
      true ->
        []

      false ->
        [
          selector_type: """
          Unsupported selector type #{inspect(selector_type)}.
          The supported selector types are: text, slug.
          """
        ]
    end
  end
end

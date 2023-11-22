defmodule Sanbase.Menus.Menu do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Menus.MenuItem
  alias Sanbase.Accounts.User
  alias __MODULE__, as: Menu

  @type menu_id :: non_neg_integer()

  @type t :: %__MODULE__{}

  schema "menus" do
    field(:name, :string)
    field(:description, :string)

    has_many(:menu_items, MenuItem, foreign_key: :parent_id)

    # Indicate that if this menu is a sub-menu.
    belongs_to(:parent, Menu)
    belongs_to(:user, User)

    # The menus that do not belong to a user, but are created
    # by an admin and are accsessible to everyone.
    field(:is_global, :boolean, default: false)

    timestamps()
  end

  def create(attrs \\ %{}) do
    %Menu{}
    |> cast(attrs, [:user_id, :name, :description, :parent_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 256)
  end

  def update(menu, attrs) do
    menu
    |> cast(attrs, [:name, :description, :parent_id])
    |> validate_length(:name, min: 1, max: 256)
  end

  @doc ~s"""
  Get a menu by its id.

  The menus are accsessible if the user is the owner or if the menu is global
  """
  def by_id(id, querying_user_id) do
    base_query()
    |> where([m], m.id == ^id and (m.user_id == ^querying_user_id or m.is_global == true))
    |> preload([
      # Preload 2 levels of menu items
      # The items of the root-menu
      :menu_items,
      # The items of the sub-menus one level deep
      menu_items: [:menu, :query, :dashboard],
      menu_items: [menu: :menu_items, menu: [menu_items: [:menu, :query, :dashboard]]]
    ])
  end

  def get_for_update(id, querying_user_id) do
    base_query()
    |> where([m], m.id == ^id and m.user_id == ^querying_user_id)
    |> lock("FOR UPDATE")
  end

  defp base_query() do
    __MODULE__
  end
end

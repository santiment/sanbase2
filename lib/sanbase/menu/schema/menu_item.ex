defmodule Sanbase.Menus.MenuItem do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Menus.Menu
  alias Sanbase.Queries.Query
  alias Sanbase.Dashboards.Dashboard

  @type t :: %__MODULE__{
          parent_id: Menu.menu_id(),
          position: integer(),
          query_id: Query.query_id(),
          dashboard_id: Dashboard.dashboard_id(),
          menu_id: Menu.menu_id(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @timestamps_opts [type: :utc_datetime]
  schema "menu_items" do
    belongs_to(:parent, Menu)

    belongs_to(:query, Query)
    belongs_to(:dashboard, Dashboard)
    belongs_to(:menu, Menu)

    field(:position, :integer)

    timestamps()
  end

  def get_for_update(id, user_id) do
    base_query()
    |> join(:left, [mi], p in Menu, on: mi.parent_id == p.id, as: :parent)
    |> where([mi, parent: p], mi.id == ^id and p.user_id == ^user_id)
    |> lock("FOR UPDATE")
  end

  @doc ~s"""
  Get the next position for a menu item inside a specific menu
  (it can be either sub-menu or a root menu)
  """
  def get_next_position(parent_menu_id) do
    base_query()
    |> where([m], m.parent_id == ^parent_menu_id)
    |> select([m], coalesce(max(m.position), 0) + 1)
  end

  @doc ~s"""
  Get the next position for a menu item inside a specific menu
  (it can be either sub-menu or a root menu)
  """
  def inc_all_positions_after(parent_menu_id, position) do
    base_query()
    |> where([m], m.parent_id == ^parent_menu_id and m.position >= ^position)
    |> update([m], inc: [position: +1])
  end

  def create(attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [
      # Who this item belongs to
      :parent_id,
      # What is the item. There's check constraint on the DB level that only one
      # of these can be set
      :menu_id,
      :query_id,
      :dashboard_id,
      # The position of the item in the menu
      :position
    ])
    |> validate_required([:parent_id, :position])
  end

  def update(menu, attrs) do
    menu
    # Do not allow to change the entity. Prefer deleting and adding a new item instead.
    |> cast(attrs, [:parent_id, :position])
  end

  # Private functions

  defp base_query() do
    from(m in __MODULE__)
  end
end

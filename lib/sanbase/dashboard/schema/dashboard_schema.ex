defmodule Sanbase.Dashboard.Schema do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.Dashboard.Panel

  @type schema_args :: %{
          name: String.t(),
          description: String.t(),
          is_public: boolean(),
          user_id: non_neg_integer()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          description: String.t(),
          is_public: boolean(),
          panels: list(Panel.t()),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t(),
          user: %User{}
        }

  schema "dashboards" do
    field(:name, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)

    belongs_to(:user, User)

    embeds_many(:panels, Panel, on_replace: :delete)

    timestamps()
  end

  @spec by_id(non_neg_integer()) ::
          {:ok, t()} | {:error, String.t()}
  def by_id(dashboard_id) do
    case Sanbase.Repo.get(__MODULE__, dashboard_id) do
      nil -> {:error, "Dashboard does not exist"}
      %__MODULE__{} = dashboard -> {:ok, dashboard}
    end
  end

  def get_access_data(dashboard_id) do
    result =
      from(d in __MODULE__,
        where: d.id == ^dashboard_id,
        select: %{user_id: d.user_id, is_public: d.is_public}
      )
      |> Sanbase.Repo.one()

    case result do
      nil -> {:error, "Dashboard does not exist"}
      data -> {:ok, data}
    end
  end

  @doc ~s"""
  Create a new, empty dashboard.
  """
  @spec new(schema_args()) :: {:ok, t()} | {:error, Changeset.t()}
  def new(args) do
    %__MODULE__{}
    |> cast(args, [:name, :description, :is_public, :user_id])
    |> validate_required([:name, :user_id])
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Update a dashboard.
  """
  @spec update(t(), schema_args()) :: {:ok, t()} | {:error, Changeset.t()}
  def update(%__MODULE__{} = dashboard, args) do
    dashboard
    |> cast(args, [:name, :description, :is_public, :user_id])
    |> Sanbase.Repo.update()
  end

  @doc ~s"""
  Add a panel to the dashboard
  """
  @spec add_panel(non_neg_integer(), Panel.panel_args()) ::
          {:ok, t()} | {:error, Changeset.t()}
  @spec add_panel(non_neg_integer(), Panel.t()) ::
          {:ok, t()} | {:error, Changeset.t()}
  def add_panel(dashboard_id, %Panel{} = panel) do
    {:ok, dashboard} = by_id(dashboard_id)

    dashboard
    |> change()
    |> put_embed(:panels, [panel] ++ dashboard.panels)
    |> Sanbase.Repo.update()
  end

  def add_panel(dashboard_id, panel_args) when is_map(panel_args) do
    {:ok, panel} = Panel.new(panel_args)
    add_panel(dashboard_id, panel)
  end

  @doc ~s"""
  Remove a panel from the dashboard.
  """
  @spec remove_panel(non_neg_integer(), non_neg_integer()) ::
          {:ok, t()} | {:error, Changeset.t()}
  def remove_panel(dashboard_id, panel_id) do
    {:ok, dashboard} = by_id(dashboard_id)
    panels = Enum.reject(dashboard.panels, &(&1.id == panel_id))

    dashboard
    |> change()
    |> put_embed(:panels, panels)
    |> Sanbase.Repo.update()
  end

  @doc ~s"""
  Update a panel on a dashboard.
  This operation preserves the panel id
  """
  @spec update_panel(non_neg_integer(), non_neg_integer(), Panel.panel_args()) ::
          {:ok, t()} | {:error, :dashboard_panel_does_not_exist}
  def update_panel(dashboard_id, panel_id, panel_args) do
    {:ok, dashboard} = by_id(dashboard_id)

    case Enum.find(dashboard.panels, &(&1.id == panel_id)) do
      nil ->
        {:error, :dashboard_panel_does_not_exist}

      panel ->
        {:ok, panel} = Panel.update(panel, panel_args)
        {:ok, _} = remove_panel(dashboard_id, panel_id)
        {:ok, _} = add_panel(dashboard_id, panel)
    end
  end
end

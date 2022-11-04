defmodule Sanbase.Dashboard.DiscordDashboard do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Dashboard
  alias Sanbase.Repo
  alias Sanbase.Accounts.User

  schema "discord_dashboard" do
    field(:channel, :string)
    field(:discord_user, :string)
    field(:guild, :string)
    field(:name, :string)
    field(:panel_id, :string)
    field(:pinned, :boolean, default: false)

    belongs_to(:user, User)
    belongs_to(:dashboard, Dashboard.Schema)
    timestamps()
  end

  @doc false
  def changeset(discord_dashboard, attrs) do
    discord_dashboard
    |> cast(attrs, [
      :panel_id,
      :name,
      :discord_user,
      :channel,
      :guild,
      :pinned,
      :user_id,
      :dashboard_id
    ])

    # |> validate_required([:panel_id, :name, :discord_user, :channel, :guild])
  end

  def list_pinned_channel(channel, guild) do
    from(d in __MODULE__, where: d.pinned == true and d.channel == ^channel and d.guild == ^guild)
    |> Repo.all()
  end

  def list_pinned_global(guild) do
    from(d in __MODULE__, where: d.pinned == true and d.guild == ^guild)
    |> Repo.all()
  end

  def pin(panel_id) do
    by_panel_id(panel_id)
    |> case do
      dashboard -> do_update(dashboard, %{pinned: true})
      nil -> {:error, :not_found}
    end
  end

  def by_panel_id(panel_id) do
    from(d in __MODULE__, where: d.panel_id == ^panel_id, preload: [:dashboard])
    |> Repo.one()
  end

  def do_update(dashboard, params) do
    dashboard
    |> changeset(params)
    |> Repo.update()
  end

  def do_create(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def create(user_id, query, params) do
    args =
      Map.take(params, [:name, :discord_user, :channel, :guild, :pinned])
      |> Map.put(:user_id, user_id)

    with {:ok, dashboard} <- Dashboard.create(%{name: params.name}, user_id),
         {:ok, %{panel: panel}} <-
           Dashboard.create_panel(dashboard.id, %{
             name: params.name,
             sql: %{parameters: %{}, query: query}
           }),
         {:ok, %__MODULE__{} = discord_dashboard} <-
           do_create(Map.merge(args, %{dashboard_id: dashboard.id, panel_id: panel.id})),
         {:ok, result} <-
           Dashboard.compute_panel(dashboard.id, panel.id, user_id, parameters: nil) do
      {:ok, result, panel.id}
    end
  end
end

defmodule Sanbase.Dashboard.DiscordDashboard do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Dashboard
  alias Sanbase.Repo
  alias Sanbase.Accounts.User

  schema "discord_dashboards" do
    field(:channel, :string)
    field(:discord_user, :string)
    field(:guild, :string)
    field(:name, :string)
    field(:panel_id, :string)
    field(:pinned, :boolean, default: false)
    field(:discord_user_id, :string)
    field(:discord_user_handle, :string)
    field(:discord_message_id, :string)

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
      :dashboard_id,
      :discord_user_id,
      :discord_user_handle,
      :discord_message_id
    ])
  end

  def list_pinned_channel(channel, guild) do
    from(d in __MODULE__,
      where: d.pinned == true and d.channel == ^channel and d.guild == ^guild,
      order_by: [asc: d.id]
    )
    |> Repo.all()
  end

  def list_pinned_global(guild) do
    from(d in __MODULE__, where: d.pinned == true and d.guild == ^guild)
    |> Repo.all()
  end

  def pin_by_msg_id(message_id) do
    by_discord_message_id(message_id)
    |> case do
      %__MODULE__{} = dashboard -> do_update(dashboard, %{pinned: true})
      nil -> {:error, :not_found}
    end
  end

  def pin(panel_id) do
    by_panel_id(panel_id)
    |> case do
      %__MODULE__{} = dashboard -> do_update(dashboard, %{pinned: true})
      nil -> {:error, :not_found}
    end
  end

  def unpin(panel_id) do
    by_panel_id(panel_id)
    |> case do
      %__MODULE__{} = dashboard -> do_update(dashboard, %{pinned: false})
      nil -> {:error, :not_found}
    end
  end

  def update_message_id(panel_id, message_id) do
    by_panel_id(panel_id)
    |> case do
      %__MODULE__{} = dashboard -> do_update(dashboard, %{discord_message_id: message_id})
      nil -> {:error, :not_found}
    end
  end

  def by_panel_id(panel_id) do
    from(d in __MODULE__, where: d.panel_id == ^panel_id, preload: [:dashboard])
    |> Repo.one()
  end

  def by_discord_message_id(message_id) do
    from(d in __MODULE__, where: d.discord_message_id == ^message_id, preload: [:dashboard])
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

  def execute(user_id, panel_id) do
    with %__MODULE__{dashboard_id: dashboard_id} = dd <- by_panel_id(panel_id),
         {:ok, result} <-
           Dashboard.compute_panel(dashboard_id, panel_id, user_id, parameters: nil) do
      {:ok, result, dd}
    else
      {:error, reason} -> {:execution_error, reason}
    end
  end

  def create(user_id, query, params) do
    args = Map.put(params, :user_id, user_id)

    create_panel_args = %{name: params.name, sql: %{parameters: %{}, query: query}}

    with {:ok, dashboard} <- Dashboard.create(%{name: params.name}, user_id),
         {:ok, %{panel: panel}} <- Dashboard.create_panel(dashboard.id, create_panel_args),
         {:ok, %__MODULE__{}} <-
           do_create(Map.merge(args, %{dashboard_id: dashboard.id, panel_id: panel.id})),
         {:ok, result} <-
           Dashboard.compute_panel(dashboard.id, panel.id, user_id, parameters: nil) do
      {:ok, result, panel.id}
    end
  end
end

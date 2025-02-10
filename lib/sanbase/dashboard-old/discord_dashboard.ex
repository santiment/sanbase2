defmodule Sanbase.Dashboard.DiscordDashboard do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Dashboard
  alias Sanbase.Repo

  schema "discord_dashboards" do
    field(:guild, :string)
    field(:channel, :string)
    field(:guild_name, :string)
    field(:channel_name, :string)
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
    cast(discord_dashboard, attrs, [
      :panel_id,
      :name,
      :channel,
      :guild,
      :channel_name,
      :guild_name,
      :pinned,
      :user_id,
      :dashboard_id,
      :discord_user_id,
      :discord_user_handle,
      :discord_message_id
    ])
  end

  def list_pinned_channel(channel, guild) do
    Repo.all(
      from(d in __MODULE__,
        where: d.pinned == true and d.channel == ^channel and d.guild == ^guild,
        order_by: [asc: d.id]
      )
    )
  end

  def list_pinned_global(guild) do
    Repo.all(from(d in __MODULE__, where: d.pinned == true and d.guild == ^guild))
  end

  def pin_by_msg_id(message_id) do
    message_id
    |> by_discord_message_id()
    |> case do
      %__MODULE__{} = dashboard -> do_update(dashboard, %{pinned: true})
      nil -> {:error, :not_found}
    end
  end

  def pin(panel_id) do
    panel_id
    |> by_panel_id()
    |> case do
      %__MODULE__{} = dashboard -> do_update(dashboard, %{pinned: true})
      nil -> {:error, :not_found}
    end
  end

  def unpin(panel_id) do
    panel_id
    |> by_panel_id()
    |> case do
      %__MODULE__{} = dashboard -> do_update(dashboard, %{pinned: false})
      nil -> {:error, :not_found}
    end
  end

  def update_message_id(panel_id, message_id) do
    panel_id
    |> by_panel_id()
    |> case do
      %__MODULE__{} = dashboard -> do_update(dashboard, %{discord_message_id: message_id})
      nil -> {:error, :not_found}
    end
  end

  def by_panel_id(panel_id) do
    Repo.one(from(d in __MODULE__, where: d.panel_id == ^panel_id, preload: [:dashboard]))
  end

  def by_discord_message_id(message_id) do
    Repo.one(from(d in __MODULE__, where: d.discord_message_id == ^message_id, preload: [:dashboard]))
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

  def execute(user_id, panel_id, discord_args) do
    with %__MODULE__{dashboard_id: dashboard_id} = dd <- by_panel_id(panel_id),
         {:ok, result} <-
           Dashboard.compute_and_store_panel(
             dashboard_id,
             panel_id,
             query_metadata(user_id, discord_args)
           ) do
      {:ok, result, dd.dashboard, dashboard_id}
    else
      {:error, reason} -> {:execution_error, reason}
    end
  end

  def create(user_id, query, params) do
    args = Map.put(params, :user_id, user_id)

    create_panel_args = %{name: params.name, sql: %{parameters: %{}, query: query}}

    with {:ok, dashboard} <- Dashboard.create(%{name: params.name, is_public: true}, user_id),
         {:ok, %{panel: panel}} <- Dashboard.create_panel(dashboard.id, create_panel_args),
         {:ok, %__MODULE__{} = dd} <-
           do_create(Map.merge(args, %{dashboard_id: dashboard.id, panel_id: panel.id})),
         {:ok, result} <-
           Dashboard.compute_and_store_panel(dashboard.id, panel.id, query_metadata(user_id, dd)) do
      {:ok, result, dashboard, panel.id}
    end
  end

  defp query_metadata(user_id, %{
         guild: guild,
         channel: channel,
         channel_name: channel_name,
         guild_name: guild_name,
         discord_user_handle: discord_user_handle
       }) do
    %{
      product: "discord-bot",
      sanbase_user_id: user_id,
      discord_guild: guild,
      discord_channel: channel,
      discord_guild_name: guild_name,
      discord_channel_name: channel_name,
      discord_user: discord_user_handle
    }
  end
end

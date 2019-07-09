defmodule Sanbase.UserList.Settings do
  @moduledoc ~s"""
  Store and work with settings specific for a single watchlist
  """

  defmodule WatchlistSettings do
    use Ecto.Schema

    import Ecto.Changeset

    @default_page_size 20
    @default_time_window "180d"
    @default_table_columns %{}

    embedded_schema do
      field(:page_size, :integer, default: @default_page_size)
      field(:time_window, :string, default: @default_time_window)
      field(:table_columns, :map, default: @default_table_columns)
    end

    def changeset(%__MODULE__{} = settings, attrs \\ %{}) do
      settings
      |> cast(attrs, [:page_size, :time_window, :table_columns])
      |> validate_number(:page_size, greater_than: 0)
      |> validate_change(:time_window, &valid_time_window?/2)
    end

    def default_settings() do
      %{
        page_size: @default_page_size,
        time_window: @default_time_window,
        table_columns: @default_table_columns
      }
    end

    # Private functions

    defp valid_time_window?(:time_window, time_window) do
      case Sanbase.Validation.valid_time_window?(time_window) do
        :ok -> []
        {:error, error} -> [time_window: error]
      end
    end
  end

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.UserList
  alias __MODULE__.WatchlistSettings

  @primary_key false
  schema "watchlist_settings" do
    belongs_to(:user, User, foreign_key: :user_id, primary_key: true)
    belongs_to(:watchlist, UserList, foreign_key: :watchlist_id, primary_key: true)

    embeds_one(:settings, WatchlistSettings)
  end

  def changeset(%__MODULE__{} = settings, attrs \\ %{}) do
    settings
    |> cast(attrs, [:user_id, :watchlist_id])
    |> cast_embed(:settings,
      required: true,
      with: &WatchlistSettings.changeset/2
    )
  end

  def settings_for(%UserList{} = ul, %User{} = user) do
    settings =
      get_settings(ul.id, user.id) ||
        get_settings(ul.id, ul.user_id) ||
        WatchlistSettings.default_settings()

    {:ok, settings}
  end

  def settings_for(%UserList{} = ul, _) do
    get_settings(ul.id, ul.user_id)
  end

  def update_or_create_settings(watchlist_id, user_id, settings) do
    case Repo.one(settings_query(watchlist_id, user_id)) do
      nil ->
        changeset(%__MODULE__{}, %{
          user_id: user_id,
          watchlist_id: watchlist_id,
          settings: settings
        })
        |> Repo.insert()

      %__MODULE__{} = ws ->
        changeset(ws, %{settings: settings})
        |> Repo.update()
    end
  end

  # Private functions

  defp get_settings(watchlist_id, user_id) do
    from(s in settings_query(watchlist_id, user_id), select: s.settings)
    |> Repo.one()
  end

  defp settings_query(watchlist_id, user_id) do
    from(s in __MODULE__,
      where: s.watchlist_id == ^watchlist_id and s.user_id == ^user_id
    )
  end
end

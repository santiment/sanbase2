defmodule Sanbase.UserList.Settings do
  @moduledoc ~s"""
  Store and work with settings specific for a watchlist.

  The settings are stored per user. One watchlist can have many settings for many
  users. When a user requires the settings for a watchlist the resolution process
  is the first one that matches:
  1. If the requesting user has defined settings - return them.
  2. If the watchlist craetor has defined settings - return them.
  3. Return the default settings
  """

  defmodule WatchlistSettings do
    @moduledoc ~s"""
    Embeded schema that defines how the settings look like
    """
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %{
            page_size: non_neg_integer(),
            table_columns: map(),
            time_window: String.t(),
            json_data: map()
          }

    @default_page_size 20
    @default_time_window "180d"
    @default_table_columns %{}
    @default_json_data %{}

    embedded_schema do
      field(:page_size, :integer, default: @default_page_size)
      field(:time_window, :string, default: @default_time_window)
      field(:table_columns, :map, default: @default_table_columns)
      field(:json_data, :map, default: @default_json_data)
    end

    def changeset(%__MODULE__{} = settings, attrs \\ %{}) do
      settings
      |> cast(attrs, [:page_size, :time_window, :table_columns, :json_data])
      |> validate_number(:page_size, greater_than: 0)
      |> validate_change(:time_window, &valid_time_window?/2)
    end

    def default_settings() do
      %{
        page_size: @default_page_size,
        time_window: @default_time_window,
        table_columns: @default_table_columns,
        json_data: @default_json_data
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
  alias Sanbase.Accounts.User
  alias Sanbase.UserList
  alias __MODULE__.WatchlistSettings

  @type t :: %__MODULE__{
          user_id: non_neg_integer(),
          watchlist_id: non_neg_integer(),
          settings: WatchlistSettings.t()
        }
  @primary_key false
  schema "watchlist_settings" do
    belongs_to(:user, User, foreign_key: :user_id, primary_key: true)
    belongs_to(:watchlist, UserList, foreign_key: :watchlist_id, primary_key: true)

    embeds_one(:settings, WatchlistSettings, on_replace: :update)
  end

  def changeset(%__MODULE__{} = settings, attrs \\ %{}) do
    settings
    |> cast(attrs, [:user_id, :watchlist_id])
    |> cast_embed(:settings,
      required: true,
      with: &WatchlistSettings.changeset/2
    )
  end

  @doc ~s"""
  Return the settings for a watchlist and a given user. Returns the first one that
  exists:
  1. User's settings for that watchlist
  2. The watchlist's creator's settings for that watchlist
  3. Default settings
  """
  @spec settings_for(%UserList{}, %User{} | nil) :: {:ok, WatchlistSettings.t()}
  def settings_for(%UserList{} = ul, %User{} = user) do
    settings =
      get_settings(ul.id, user.id) ||
        get_settings(ul.id, ul.user_id) ||
        WatchlistSettings.default_settings()

    {:ok, settings}
  end

  def settings_for(%UserList{} = ul, _) do
    settings =
      get_settings(ul.id, ul.user_id) ||
        WatchlistSettings.default_settings()

    {:ok, settings}
  end

  @doc ~s"""
  Create or update settings for a given watchlist and user
  """
  @spec update_or_create_settings(watchlist_id, user_id, settings) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
        when watchlist_id: non_neg_integer,
             user_id: non_neg_integer,
             settings: WatchlistSettings.t()
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

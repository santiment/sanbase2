defmodule Sanbase.MonitoredTwitterHandle do
  use Ecto.Schema

  alias Sanbase.Accounts.User

  import Ecto.Query
  import Ecto.Changeset

  @type t :: %__MODULE__{
          handle: String.t(),
          notes: String.t(),
          user_id: User.user_id(),
          user: User.t(),
          origin: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "monitored_twitter_handles" do
    field(:handle, :string)
    field(:notes, :string)
    field(:origin, :string)

    belongs_to(:user, User)

    timestamps()
  end

  def is_handle_monitored(handle) do
    query = from(m in __MODULE__, where: m.handle == ^handle)
    boolean = Sanbase.Repo.exists?(query)
    {:ok, boolean}
  end

  @doc ~s"""
  Add a twitter handle to monitor
  """
  @spec add_new(String.t(), User.user_id(), String.t(), String.t()) ::
          {:ok, Sanbase.MonitoredTwitterHandle.t()} | {:error, String.t()}
  def add_new(handle, user_id, origin, notes) do
    %__MODULE__{}
    |> change(%{handle: String.downcase(handle), user_id: user_id, origin: origin, notes: notes})
    |> validate_required([:handle, :user_id, :origin])
    |> unique_constraint(:handle)
    |> Sanbase.Repo.insert()
    |> maybe_transform_error()
  end

  @doc ~s"""
  Get a list of all twitter handles that a user has submitted
  """
  @spec get_user_submissions(User.user_id()) :: {:ok, [t()]}
  def get_user_submissions(user_id) do
    query = from(m in __MODULE__, where: m.user_id == ^user_id)

    {:ok, Sanbase.Repo.all(query)}
  end

  defp maybe_transform_error({:ok, _} = result), do: result

  defp maybe_transform_error({:error, changeset}) do
    case Sanbase.Utils.ErrorHandling.changeset_errors(changeset) do
      %{handle: ["has already been taken"]} ->
        {:error, "The provided twitter handle is already being monitored."}

      _ ->
        msg = Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)
        {:error, msg}
    end
  end
end

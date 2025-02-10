defmodule Sanbase.Accounts.LinkedUserCandidate do
  @moduledoc ~s"""
  Module for handling the candidates for linked users.

  Before linking two users both ends - primary and secondary - must
  approve of this linking. The primary user agrees to the linking
  by creating a token and sharing it with the secondary user. The
  secondary user agrees to the linking by accepting the token and
  sending it to the backend. If both actions are done within 24 hours
  of each other, the linking is considered successful.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Accounts.LinkedUser
  alias Sanbase.Accounts.User

  schema "linked_users_candidates" do
    belongs_to(:primary_user, User)
    belongs_to(:secondary_user, User)

    field(:is_confirmed, :boolean, default: false)
    field(:token, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = luc, attrs) do
    attrs = Map.put(attrs, :token, generate_token(attrs))

    cast(luc, attrs, [:primary_user_id, :secondary_user_id, :token])
  end

  def confirm_candidate(token, confirming_user_id) do
    case Sanbase.Repo.get_by(__MODULE__, token: token) do
      nil ->
        {:error, "Token not valid."}

      %__MODULE__{} = luc ->
        case is_candidate_valid(luc, confirming_user_id) do
          true -> do_confirm_candidate(luc)
          {:error, error} -> {:error, error}
        end
    end
  end

  def create(primary_user_id, secondary_user_id) do
    %__MODULE__{}
    |> changeset(%{
      primary_user_id: primary_user_id,
      secondary_user_id: secondary_user_id
    })
    |> Sanbase.Repo.insert()
  end

  def update(%__MODULE__{} = luc, attrs) do
    luc
    |> cast(attrs, [:is_confirmed])
    |> Sanbase.Repo.update()
  end

  @token_valid_window_minutes 60 * 24
  defp is_candidate_valid(%__MODULE__{} = luc, confirming_user_id) do
    case luc do
      %__MODULE__{secondary_user_id: id} when id != confirming_user_id ->
        {:error, "Token not valid."}

      %__MODULE__{is_confirmed: true} ->
        {:error, "Token has already been used."}

      %__MODULE__{inserted_at: inserted_at} ->
        naive_now = NaiveDateTime.utc_now()

        if Timex.diff(naive_now, inserted_at, :minutes) <= @token_valid_window_minutes do
          true
        else
          {:error, "Token has expired."}
        end
    end
  end

  defp do_confirm_candidate(%__MODULE__{} = luc) do
    with {:ok, _} <- LinkedUser.create(luc.primary_user_id, luc.secondary_user_id),
         {:ok, _} <- update(luc, %{is_confirmed: true}) do
      :ok
    end
  end

  defp generate_token(attrs) do
    rand_str = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64() |> binary_part(0, 16)

    "prim_#{attrs.primary_user_id}_sec_#{attrs.secondary_user_id}_#{rand_str}"
  end
end

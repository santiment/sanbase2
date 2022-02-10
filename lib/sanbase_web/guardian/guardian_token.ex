defmodule SanbaseWeb.Guardian.Token do
  use Ecto.Schema
  import Ecto.Query

  @primary_key false
  schema "guardian_tokens" do
    field(:jti, :string, primary_key: true)
    field(:typ, :string)
    field(:aud, :string)
    field(:iss, :string)
    field(:sub, :string)
    field(:exp, :integer)
    field(:jwt, :string)
    field(:claims, :map)

    field(:last_exchanged_at, :utc_datetime)
    timestamps()
  end

  def revoke(jti, user_id) do
    sub = to_string(user_id)

    from(gt in __MODULE__, select: gt, where: gt.jti == ^jti and gt.sub == ^sub)
    |> Sanbase.Repo.delete_all()
    |> case do
      {1, _} -> :ok
      _ -> {:error, "Failed revoking a refresh token"}
    end
  end

  def revoke_all_with_user_id(user_id) do
    sub = to_string(user_id)

    from(gt in __MODULE__, where: gt.sub == ^sub)
    |> Sanbase.Repo.delete_all()
    |> case do
      {num, _} when is_integer(num) -> :ok
      _ -> {:error, "Failed revoking all refresh tokens for a user"}
    end
  end

  def user_by_jti(jti) do
    query = from(gt in __MODULE__, where: gt.jti == ^jti, select: gt.sub)

    case Sanbase.Repo.one(query) do
      nil -> {:error, "No user with such jti"}
      user_id -> Sanbase.Accounts.get_user(String.to_integer(user_id))
    end
  end

  def refresh_tokens(user_id, current_refresh_token \\ nil) do
    result =
      refresh_tokens_by_user_id(user_id)
      |> Enum.map(fn token ->
        is_current = not is_nil(current_refresh_token) and current_refresh_token == token.jwt
        created_at = DateTime.from_naive!(token.inserted_at, "Etc/UTC")
        expires_at = DateTime.from_unix!(token.exp)

        %{
          type: token.typ,
          jti: token.jti,
          expires_at: expires_at,
          client: Map.get(token.claims, "client", "unknown"),
          platform: Map.get(token.claims, "platform", "unknown"),
          last_active_at: last_active_at(token, created_at, is_current),
          created_at: created_at,
          is_current: is_current,
          has_expired: DateTime.compare(DateTime.utc_now(), expires_at) == :gt
        }
      end)

    {:ok, result}
  end

  def refresh_last_exchanged_at(%{"jti" => jti} = _claims) do
    from(
      gt in __MODULE__,
      where: gt.jti == ^jti
    )
    |> Sanbase.Repo.update_all(set: [last_exchanged_at: DateTime.utc_now()])
    |> case do
      {1, _} ->
        {:ok, true}

      result ->
        {:error,
         "Error renewing last exchanged at for a refresh token. Result: #{inspect(result)}"}
    end
  end

  defp last_active_at(_token, _created_at, true = _is_current), do: DateTime.utc_now()

  defp last_active_at(token, created_at, _is_current) do
    case token.last_exchanged_at do
      %DateTime{} = dt -> dt
      _ -> created_at
    end
  end

  defp refresh_tokens_by_user_id(user_id) do
    sub = to_string(user_id)

    from(
      gt in __MODULE__,
      select: map(gt, [:jwt, :jti, :exp, :claims, :inserted_at, :typ, :last_exchanged_at]),
      where: gt.sub == ^sub and gt.typ == "refresh"
    )
    |> Sanbase.Repo.all()
  end
end

defmodule SanbaseWeb.Guardian.Token do
  use Ecto.Schema
  import Ecto.Query

  schema "guardian_tokens" do
    field(:jti, :string)
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

  def refresh_tokens(user_id, current_refresh_token \\ nil) do
    sub = to_string(user_id)

    result =
      from(
        gt in SanbaseWeb.Guardian.Token,
        select: map(gt, [:jwt, :exp, :claims, :inserted_at, :typ, :last_exchanged_at]),
        where: gt.sub == ^sub and gt.typ == "refresh"
      )
      |> Sanbase.Repo.all()
      |> Enum.map(fn %{
                       jwt: jwt,
                       exp: unix_expiry,
                       claims: claims,
                       inserted_at: created_at,
                       last_exchanged_at: last_exchanged_at,
                       typ: type
                     } ->
        is_current = not is_nil(current_refresh_token) and current_refresh_token == jwt
        created_at = DateTime.from_naive!(created_at, "Etc/UTC")

        last_active_at =
          cond do
            is_current -> DateTime.utc_now()
            last_exchanged_at == nil -> created_at
            not is_nil(last_exchanged_at) -> last_exchanged_at
          end

        %{
          type: type,
          expires_at: DateTime.from_unix!(unix_expiry),
          client: Map.get(claims, "client", "unknown"),
          platform: Map.get(claims, "platform", "unknown"),
          created_at: created_at,
          last_active_at: last_active_at,
          is_current: is_current
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
end

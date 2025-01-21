defmodule Sanbase.Accounts.AccessAttempt do
  use Ecto.Schema
  import Ecto.{Query, Changeset}
  alias Sanbase.Repo

  schema "access_attempts" do
    belongs_to(:user, Sanbase.Accounts.User)
    field(:ip_address, :string)
    field(:type, :string)

    timestamps()
  end

  def has_allowed_attempts?(type, user, remote_ip) do
    config = get_config(type)
    too_many_user_attempts? = attempts_count(type, user) > config.allowed_user_attempts
    too_many_ip_attempts? = attempts_count(type, remote_ip) > config.allowed_ip_attempts

    if too_many_user_attempts? or too_many_ip_attempts? do
      {:error, :too_many_attempts}
    else
      :ok
    end
  end

  def create(type, user, remote_ip) do
    %__MODULE__{}
    |> changeset(%{
      user_id: user && user.id,
      ip_address: remote_ip,
      type: type
    })
    |> Repo.insert()
    |> case do
      {:error, changeset} -> {:error, changeset}
      attempt -> attempt
    end
  end

  def changeset(%__MODULE__{} = attempt, attrs \\ %{}) do
    attempt
    |> cast(attrs, [:user_id, :ip_address, :type])
    |> validate_required([:ip_address, :type])
    |> foreign_key_constraint(:user_id)
  end

  defp attempts_count(type, remote_ip) when is_binary(remote_ip) do
    config = get_config(type)
    interval_limit = Timex.shift(Timex.now(), minutes: -config.interval_in_minutes)

    from(attempt in __MODULE__,
      where:
        attempt.type == ^type and
          attempt.ip_address == ^remote_ip and
          attempt.inserted_at > ^interval_limit
    )
    |> Repo.aggregate(:count, :id)
  end

  defp attempts_count(type, %{id: user_id}) do
    config = get_config(type)
    interval_limit = Timex.shift(Timex.now(), minutes: -config.interval_in_minutes)

    from(attempt in __MODULE__,
      where:
        attempt.type == ^type and
          attempt.user_id == ^user_id and
          attempt.inserted_at > ^interval_limit
    )
    |> Repo.aggregate(:count, :id)
  end

  defp get_config(type) do
    case type do
      "email_login" -> Sanbase.Accounts.EmailLoginAttempt.config()
      "coupon" -> Sanbase.Accounts.CouponAttempt.config()
      _ -> raise "Unknown access attempt type: #{type}"
    end
  end
end

defmodule Sanbase.Accounts.EmailLoginAttempt do
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.Repo

  @interval_in_minutes 5
  @allowed_login_attempts 5
  @allowed_ip_attempts 20
  @ipv6_max_length 39

  schema "email_login_attempts" do
    belongs_to(:user, Sanbase.Accounts.User)
    field(:ip_address, :string, size: @ipv6_max_length)

    timestamps()
  end

  def has_allowed_login_attempts(user, remote_ip) do
    too_many_login_attempts? = login_attempts_count(user) > @allowed_login_attempts
    too_many_ip_attempts? = login_attempts_count(remote_ip) > @allowed_ip_attempts

    if too_many_login_attempts? or too_many_ip_attempts? do
      {:error, :too_many_login_attempts}
    else
      :ok
    end
  end

  def create(%{id: user_id}, remote_ip) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, ip_address: remote_ip})
    |> Repo.insert()
    |> case do
      {:error, _} -> {:error, :too_many_login_attempts}
      attempt -> attempt
    end
  end

  def changeset(%__MODULE__{} = attempt, attrs \\ %{}) do
    attempt
    |> cast(attrs, [:user_id, :ip_address])
    |> validate_required([:user_id, :ip_address])
    |> foreign_key_constraint(:user_id)
  end

  # Private
  defp login_attempts_count(remote_ip) when is_binary(remote_ip) do
    interval_limit = Timex.shift(Timex.now(), minutes: -@interval_in_minutes)

    from(attempt in __MODULE__,
      where: attempt.ip_address == ^remote_ip and attempt.inserted_at > ^interval_limit
    )
    |> Repo.aggregate(:count, :id)
  end

  defp login_attempts_count(%{id: user_id}) do
    interval_limit = Timex.shift(Timex.now(), minutes: -@interval_in_minutes)

    from(attempt in __MODULE__,
      where: attempt.user_id == ^user_id and attempt.inserted_at > ^interval_limit
    )
    |> Repo.aggregate(:count, :id)
  end
end

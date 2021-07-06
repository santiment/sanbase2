defmodule Sanbase.Accounts.EmailLoginAttempt do
  use Ecto.Schema

  import Ecto.Query

  alias Sanbase.Repo

  @interval_in_minutes 15
  @allowed_login_attempts 5

  schema "email_login_attempts" do
    belongs_to(:user, Sanbase.Accounts.User)
    field(:ip_address, :string, size: 15)

    timestamps()
  end

  def has_allowed_login_attempts(user, remote_ip) do
    login_attempts = login_attempts_count(user, remote_ip)

    if login_attempts <= @allowed_login_attempts do
      :ok
    else
      {:error, :too_many_login_attempts}
    end
  end

  def record_login_attempt(%{id: user_id}, remote_ip) do
    %__MODULE__{user_id: user_id, ip_address: remote_ip}
    |> Repo.insert!()
  end

  # Private
  defp login_attempts_count(%{id: user_id}, remote_ip) do
    interval_limit = Timex.shift(Timex.now(), minutes: -@interval_in_minutes)

    from(attempt in __MODULE__,
      where:
        attempt.user_id == ^user_id and
          attempt.ip_address == ^remote_ip and
          attempt.inserted_at > ^interval_limit
    )
    |> Repo.aggregate(:count, :id)
  end
end

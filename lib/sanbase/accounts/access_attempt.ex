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

  def check_attempt_limit(type, user, remote_ip) do
    config = get_config(type)

    # Check burst limits (short-term)
    too_many_user_burst? = attempts_count(type, user, :burst) > config.allowed_user_burst_attempts

    too_many_ip_burst? =
      attempts_count(type, remote_ip, :burst) > config.allowed_ip_burst_attempts

    # Check daily limits (long-term)
    too_many_user_daily? = attempts_count(type, user, :daily) > config.allowed_user_daily_attempts

    too_many_ip_daily? =
      attempts_count(type, remote_ip, :daily) > config.allowed_ip_daily_attempts

    cond do
      too_many_user_burst? or too_many_ip_burst? ->
        {:error, :too_many_burst_attempts}

      too_many_user_daily? or too_many_ip_daily? ->
        {:error, :too_many_daily_attempts}

      true ->
        :ok
    end
  end

  def check_ip_attempt_limit(type, remote_ip) do
    config = get_config(type)

    # Check burst limits (short-term)
    too_many_ip_burst? =
      attempts_count(type, remote_ip, :burst) > config.allowed_ip_burst_attempts

    # Check daily limits (long-term)
    too_many_ip_daily? =
      attempts_count(type, remote_ip, :daily) > config.allowed_ip_daily_attempts

    cond do
      too_many_ip_burst? ->
        {:error, :too_many_burst_attempts}

      too_many_ip_daily? ->
        {:error, :too_many_daily_attempts}

      true ->
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

  defp attempts_count(type, remote_ip, limit_type) when is_binary(remote_ip) do
    config = get_config(type)
    interval_minutes = get_interval_minutes(config, limit_type)
    interval_limit = Timex.shift(Timex.now(), minutes: -interval_minutes)

    from(attempt in __MODULE__,
      where:
        attempt.type == ^type and
          attempt.ip_address == ^remote_ip and
          attempt.inserted_at > ^interval_limit
    )
    |> Repo.aggregate(:count, :id)
  end

  defp attempts_count(type, %{id: user_id}, limit_type) do
    config = get_config(type)
    interval_minutes = get_interval_minutes(config, limit_type)
    interval_limit = Timex.shift(Timex.now(), minutes: -interval_minutes)

    from(attempt in __MODULE__,
      where:
        attempt.type == ^type and
          attempt.user_id == ^user_id and
          attempt.inserted_at > ^interval_limit
    )
    |> Repo.aggregate(:count, :id)
  end

  defp get_interval_minutes(config, :burst), do: config.burst_interval_in_minutes
  defp get_interval_minutes(config, :daily), do: config.daily_interval_in_minutes

  defp get_config(type) do
    case type do
      "email_login" -> Sanbase.Accounts.EmailLoginAttempt.config()
      "coupon" -> Sanbase.Accounts.CouponAttempt.config()
      _ -> raise "Unknown access attempt type: #{type}"
    end
  end
end

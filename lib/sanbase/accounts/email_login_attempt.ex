defmodule Sanbase.Accounts.EmailLoginAttempt do
  @behaviour Sanbase.Accounts.AccessAttemptBehaviour
  alias Sanbase.Accounts.AccessAttempt

  @impl true
  def type, do: "email_login"

  @impl true
  def config do
    %{
      # Burst limits (short-term protection)
      burst_interval_in_minutes: 5,
      allowed_user_burst_attempts: 5,
      allowed_ip_burst_attempts: 10,

      # Daily limits (long-term protection)
      # 24 hours
      daily_interval_in_minutes: 24 * 60,
      allowed_user_daily_attempts: 20,
      allowed_ip_daily_attempts: 100
    }
  end

  @impl true
  def check_attempt_limit(user, remote_ip) do
    AccessAttempt.check_attempt_limit(type(), user, remote_ip)
  end

  def check_ip_attempt_limit(remote_ip) do
    AccessAttempt.check_ip_attempt_limit(type(), remote_ip)
  end

  @impl true
  def create(user, remote_ip) do
    AccessAttempt.create(type(), user, remote_ip)
  end
end

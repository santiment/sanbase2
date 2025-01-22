defmodule Sanbase.Accounts.EmailLoginAttempt do
  alias Sanbase.Accounts.AccessAttempt

  def config do
    %{
      interval_in_minutes: 5,
      allowed_user_attempts: 5,
      allowed_ip_attempts: 20
    }
  end

  def check_attempt_limit(user, remote_ip) do
    AccessAttempt.check_attempt_limit("email_login", user, remote_ip)
  end

  def create(user, remote_ip) do
    AccessAttempt.create("email_login", user, remote_ip)
  end
end

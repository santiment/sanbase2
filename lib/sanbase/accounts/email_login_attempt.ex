defmodule Sanbase.Accounts.EmailLoginAttempt do
  alias Sanbase.Accounts.AccessAttempt

  def config do
    %{
      interval_in_minutes: 5,
      allowed_user_attempts: 5,
      allowed_ip_attempts: 20
    }
  end

  def has_allowed_attempts?(user, remote_ip) do
    AccessAttempt.has_allowed_attempts?("email_login", user, remote_ip)
  end

  def create(user, remote_ip) do
    AccessAttempt.create("email_login", user, remote_ip)
  end
end

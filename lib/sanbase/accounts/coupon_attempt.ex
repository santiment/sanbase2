defmodule Sanbase.Accounts.CouponAttempt do
  alias Sanbase.Accounts.AccessAttempt

  def config do
    %{
      interval_in_minutes: 10,
      allowed_user_attempts: 5,
      allowed_ip_attempts: 20
    }
  end

  def has_allowed_attempts?(user, remote_ip) do
    AccessAttempt.has_allowed_attempts?("coupon", user, remote_ip)
  end

  def create(user, remote_ip) do
    AccessAttempt.create("coupon", user, remote_ip)
  end
end

defmodule Sanbase.Accounts.NewsletterVerifyAttempt do
  @moduledoc ~s"""
  Limits the public `verifyEmailNewsletter` mutation, which sends an email to
  an arbitrary address. Only the per-IP limit is used, there is no user.
  """
  alias Sanbase.Accounts.AccessAttempt

  def type, do: "newsletter_verify"

  def config do
    %{
      interval_in_minutes: 5,
      allowed_user_attempts: 5,
      allowed_ip_attempts: 5,
      # Allow exactly 5 requests per IP per interval, not 6.
      reject_at_limit: true
    }
  end

  def check_ip_attempt_limit(remote_ip) do
    AccessAttempt.check_ip_attempt_limit(type(), remote_ip)
  end

  def create(remote_ip) do
    AccessAttempt.create(type(), nil, remote_ip)
  end
end

defmodule Sanbase.Accounts.AccessAttemptBehaviour do
  @callback config() :: %{
              interval_in_minutes: pos_integer(),
              allowed_user_attempts: pos_integer(),
              allowed_ip_attempts: pos_integer()
            }

  @callback type() :: String.t()

  @callback check_attempt_limit(user :: term(), remote_ip :: String.t()) ::
              :ok | {:error, atom()}

  @callback create(user :: term(), remote_ip :: String.t()) ::
              {:ok, term()} | {:error, term()}
end

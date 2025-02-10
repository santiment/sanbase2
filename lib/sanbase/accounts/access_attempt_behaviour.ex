defmodule Sanbase.Accounts.AccessAttemptBehaviour do
  @moduledoc false
  @callback config() :: %{
              interval_in_minutes: pos_integer(),
              allowed_user_attempts: pos_integer(),
              allowed_ip_attempts: pos_integer()
            }

  @callback type() :: String.t()

  @callback check_attempt_limit(user :: term(), remote_ip :: String.t()) ::
              :ok | {:error, :too_many_attempts}

  @callback create(user :: term(), remote_ip :: String.t()) ::
              {:ok, term()} | {:error, term()}
end

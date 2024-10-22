defmodule Sanbase.Notifications.EmailClientBehaviour do
  @callback send_email(to :: String.t(), subject :: String.t(), body :: String.t()) ::
              :ok | {:error, term()}
end

defmodule Sanbase.Notifications.EmailClient do
  @behaviour Sanbase.Notifications.EmailClientBehaviour

  def send_email(to, subject, body), do: :ok
end

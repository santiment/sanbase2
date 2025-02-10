defmodule Sanbase.Notifications.EmailClientBehaviour do
  @moduledoc false
  @callback send_email(to :: String.t(), subject :: String.t(), body :: String.t()) ::
              :ok | {:error, term()}
end

defmodule Sanbase.Notifications.EmailClient do
  @moduledoc false
  @behaviour Sanbase.Notifications.EmailClientBehaviour

  def send_email(_to, _subject, _body), do: :ok
end

defmodule Sanbase.Auth.Apikey do
  defdelegate api_key_secret_to_user(apikey), to: Sanbase.Auth.Hmac
end

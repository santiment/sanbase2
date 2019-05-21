defmodule Sanbase.ExAdmin.Auth.UserApikeyToken do
  use ExAdmin.Register

  register_resource Sanbase.Auth.UserApikeyToken do
    # Showing the apikey token is safe as the whole apikey cannot be generated
    # out of it. To generate the whole apikey a secret key, known only by the
    # server is needed.
    action_items(only: [:show])
  end
end

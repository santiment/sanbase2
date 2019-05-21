defmodule Sanbase.ExAdmin.Auth.UserApikeyToken do
  use ExAdmin.Register

  register_resource Sanbase.Auth.UserApikeyToken do
    # Showing the apikey token is safe as the whole apikey cannot be generated
    # out of it. To generate the whole apikey a secret key, known only by the
    # server is needed.
    action_items(only: [:show])

    csv([
      {"Id", & &1.id},
      {"Token", & &1.token},
      {"User Id", & &1.user.id},
      {"User Email", & &1.user.email},
      {"Username", & &1.user.username},
      {"Inserted at", & &1.inserted_at},
      {"Updated at", & &1.updated_at}
    ])
  end
end

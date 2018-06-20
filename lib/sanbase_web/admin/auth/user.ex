defmodule Sanbase.ExAdmin.Auth.User do
  use ExAdmin.Register

  register_resource Sanbase.Auth.User do
    form user do
      inputs do
        input(user, :test_san_balance)
      end
    end
  end
end

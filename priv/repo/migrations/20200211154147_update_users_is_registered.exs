defmodule Sanbase.Repo.Migrations.UpdateUsersIsRegistered do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  def up do
    setup()

    from(u in User, preload: [:eth_accounts])
    |> Repo.all()
    |> Enum.each(fn user ->
      user
      |> User.changeset(%{
        is_registered:
          user.privacy_policy_accepted || !is_nil(user.email_token_validated_at) ||
            user.eth_accounts != []
      })
      |> Repo.update()
    end)
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end

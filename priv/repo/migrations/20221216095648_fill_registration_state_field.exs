defmodule Sanbase.Repo.Migrations.FillRegistrationStateField do
  use Ecto.Migration

  import Ecto.Query

  def up do
    setup()
    registration_state = %{"state" => "finished", "data" => %{}}

    from(
      user in Sanbase.Accounts.User,
      where: user.is_registered == true,
      update: [set: [registration_state: ^registration_state]]
    )
    |> Sanbase.Repo.update_all([])
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end

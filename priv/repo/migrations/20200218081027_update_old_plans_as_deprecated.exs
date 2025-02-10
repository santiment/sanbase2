defmodule Sanbase.Repo.Migrations.UpdateOldPlansAsDeprecated do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("UPDATE plans SET is_deprecated='t' where id IN (2, 3, 4, 6, 7, 8)")
  end

  def down do
    execute("UPDATE plans SET is_deprecated='f' where id IN (2, 3, 4, 6, 7, 8)")
  end
end

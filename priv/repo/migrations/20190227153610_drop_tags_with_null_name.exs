defmodule Sanbase.Repo.Migrations.DropTagsWithNullName do
  use Ecto.Migration
  import Ecto.Query

  def up() do
    from(t in Sanbase.Tag, where: is_nil(t.name))
    |> Sanbase.Repo.delete_all()
  end

  def down(), do: :ok
end

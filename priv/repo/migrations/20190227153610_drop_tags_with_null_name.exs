defmodule Sanbase.Repo.Migrations.DropTagsWithNullName do
  use Ecto.Migration
  import Ecto.Query

  def up() do
    # NOTE: This is a workaround for how the ecto prometheus exporter works
    # `delete_all` tries to write data in an ETS table that is started during
    # application start. `delete_all` does not raise exceptions on some failure
    # so the try/rescue block is concerning the exception raised by the prometheus
    # exporter
    try do
      from(t in Sanbase.Tag, where: is_nil(t.name))
      |> Sanbase.Repo.delete_all()
    rescue
      _ -> :ok
    end
  end

  def down(), do: :ok
end

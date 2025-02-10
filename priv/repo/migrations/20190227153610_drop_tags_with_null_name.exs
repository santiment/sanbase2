defmodule Sanbase.Repo.Migrations.DropTagsWithNullName do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  # NOTE: This is a workaround for how the ecto prometheus exporter works
  # `delete_all` tries to write data in an ETS table that is started during
  # application start. `delete_all` does not raise exceptions on some failure
  # so the try/rescue block is concerning the exception raised by the prometheus
  # exporter
  def up do
    Sanbase.Repo.delete_all(from(t in Sanbase.Tag, where: is_nil(t.name)))
  rescue
    _ -> :ok
  end

  def down, do: :ok
end

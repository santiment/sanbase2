defmodule Sanbase.Knowledge.Faq do
  alias Sanbase.Repo
  alias Sanbase.Knowledge.FaqEntry
  import Ecto.Query

  def list_entries do
    FaqEntry
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  def get_entry!(id) do
    Repo.get!(FaqEntry, id)
  end

  def create_entry(attrs \\ %{}) do
    %FaqEntry{}
    |> FaqEntry.changeset(attrs)
    |> Repo.insert()
  end

  def update_entry(%FaqEntry{} = entry, attrs) do
    entry
    |> FaqEntry.changeset(attrs)
    |> Repo.update()
  end

  def delete_entry(%FaqEntry{} = entry) do
    Repo.delete(entry)
  end

  def change_entry(%FaqEntry{} = entry, attrs \\ %{}) do
    FaqEntry.changeset(entry, attrs)
  end
end

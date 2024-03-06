defmodule SanbaseWeb.GenericAdmin.Ecosystem do
  def schema_module, do: Sanbase.Ecosystem

  def resource() do
    %{
      actions: [:new, :edit],
      index_fields: [:id, :ecosystem, :inserted_at, :updated_at],
      new_fields: [:ecosystem],
      edit_fields: [:ecosystem],
      preloads: [:projects],
      belongs_to_fields: %{}
    }
  end
end

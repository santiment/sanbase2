defmodule SanbaseWeb.GenericAdmin.Report do
  def schema_module, do: Sanbase.Report

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [:name, :description, :is_pro, :is_published, :inserted_at, :updated_at],
      new_fields: [:name, :description, :is_pro, :is_published, :tags],
      edit_fields: [:name, :description, :is_pro, :is_published, :tags]
    }
  end
end

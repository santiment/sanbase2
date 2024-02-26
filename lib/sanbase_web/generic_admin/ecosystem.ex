defmodule SanbaseWeb.GenericAdmin.Ecosystem do
  def schema_module, do: Sanbase.Ecosystem

  def resource() do
    %{
      actions: [:new, :edit],
      new_fields: [:ecosystem],
      edit_fields: [:ecosystem]
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.FeatureToggle do
  @moduledoc """
  Admin page for the feature toggles. Only `enabled` can be edited, so the
  toggles cannot be created, renamed or deleted from the admin panel. The
  toggle rows are inserted by migrations.

  Toggles are read from the database on every check, so a change made here
  applies immediately.
  """

  @behaviour SanbaseWeb.GenericAdmin

  def schema_module(), do: Sanbase.FeatureToggle
  def resource_name(), do: "feature_toggles"
  def singular_resource_name(), do: "feature_toggle"

  def resource() do
    %{
      actions: [:edit],
      index_fields: [:id, :name, :enabled, :updated_at],
      edit_fields: [:enabled]
    }
  end
end

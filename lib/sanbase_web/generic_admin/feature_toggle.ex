defmodule SanbaseWeb.GenericAdmin.FeatureToggle do
  @moduledoc """
  Admin page for the feature toggles. Only `enabled` can be edited, so the
  toggles cannot be created, renamed or deleted from the admin panel. The
  toggle rows are inserted by migrations.

  Toggles are read from the database on every check, so a change made here
  applies immediately.

  Turning `business_reduced_api_calls` off also refreshes the API call limits of
  every customer on the reduced Business allowance (`after_filter/3`), so they are
  back on the old allowance at once.
  """

  @behaviour SanbaseWeb.GenericAdmin

  def schema_module(), do: Sanbase.FeatureToggle
  def resource_name(), do: "feature_toggles"
  def singular_resource_name(), do: "feature_toggle"

  def resource() do
    %{
      actions: [:edit],
      index_fields: [:id, :name, :enabled, :enabled_at, :updated_at],
      edit_fields: [:enabled]
    }
  end

  def after_filter(%Sanbase.FeatureToggle{enabled: false, name: name}, _changeset, _params) do
    if name == Sanbase.FeatureToggle.business_reduced_api_calls_name() do
      case Sanbase.ApiCallLimit.BusinessAllowance.refresh_reduced() do
        %{failed: []} ->
          :ok

        %{failed: ids} ->
          {:error, "could not refresh the API call limits of users #{inspect(ids)}"}
      end
    else
      :ok
    end
  end

  def after_filter(_toggle, _changeset, _params), do: :ok
end

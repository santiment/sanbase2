defmodule SanbaseWeb.GenericAdmin.FeatureToggle do
  @moduledoc """
  Admin page for the feature toggles. Only `enabled` can be edited, so the
  toggles cannot be created, renamed or deleted from the admin panel. The
  toggle rows are inserted by migrations.

  Toggles are read from the database on every check, so a change made here
  applies immediately.

  Turning `business_reduced_api_calls` on or off also refreshes the API call limits
  of every customer still on the reduced Business allowance from before
  (`after_filter/3`), so they go back on the old allowance. See
  `Sanbase.ApiCallLimit.BusinessAllowance`.
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

  def after_filter(%Sanbase.FeatureToggle{name: name}, changeset, _params) do
    business_toggle_changed? =
      name == Sanbase.FeatureToggle.business_reduced_api_calls_name() and
        Ecto.Changeset.changed?(changeset, :enabled)

    if business_toggle_changed?, do: refresh_reduced(), else: :ok
  end

  defp refresh_reduced() do
    case Sanbase.ApiCallLimit.BusinessAllowance.refresh_reduced() do
      %{failed: []} ->
        :ok

      %{failed: ids} ->
        {:error, "could not refresh the API call limits of users #{inspect(ids)}"}

      {:error, message} ->
        {:error, message}
    end
  end
end

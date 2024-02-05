defmodule SanbaseWeb.GenericAdmin.UserAffiliateDetails do
  alias Sanbase.Affiliate.UserAffiliateDetails

  @schema_module UserAffiliateDetails
  @resource %{
    preloads: [:user],
    edit_fields: [:telegram_handle, :marketing_channels]
  }

  def schema_module, do: @schema_module
  def resource, do: @resource
end

defmodule SanbaseWeb.GenericAdmin.UserAffiliateDetails do
  @behaviour SanbaseWeb.GenericAdmin
  alias Sanbase.Affiliate.UserAffiliateDetails

  @schema_module UserAffiliateDetails
  @resource %{
    actions: [:new, :edit],
    preloads: [:user],
    edit_fields: [:telegram_handle, :marketing_channels]
  }

  def schema_module, do: @schema_module
  def resource_name, do: "user_affiliate_details"
  def singular_resource_name, do: "user_affiliate_detail"
  def resource, do: @resource
end

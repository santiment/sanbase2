defmodule SanbaseWeb.GenericAdmin.UserAffiliateDetails do
  alias Sanbase.Affiliate.UserAffiliateDetails

  @resource %{
    "user_affiliate_details" => %{
      module: UserAffiliateDetails,
      admin_module: __MODULE__,
      singular: "user_affiliate_details",
      preloads: [:user],
      actions: [:show, :edit],
      edit_fields: [:telegram_handle, :marketing_channels]
    }
  }

  def resource, do: @resource
end

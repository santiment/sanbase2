defmodule SanbaseWeb.GenericAdmin do
  @modules [
    SanbaseWeb.GenericAdmin.User,
    SanbaseWeb.GenericAdmin.Subscription,
    SanbaseWeb.GenericAdmin.UserAffiliateDetails
  ]
  @resource_module_map Enum.reduce(@modules, %{}, fn m, acc ->
                         Map.merge(acc, m.resource())
                       end)

  def resource_module_map, do: @resource_module_map
end

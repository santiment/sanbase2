defmodule SanbaseWeb.ExAdmin.ApiCallLimit do
  use ExAdmin.Register

  register_resource Sanbase.ApiCallLimit do
    index do
      column(:id)
      column(:user, link: true)
      column(:remote_ip)
      column(:has_limits)
      column(:api_calls_limit_plan)
      column(:api_calls)
    end

    show acl do
      attributes_table(all: true)
    end

    form acl do
      inputs do
        input(acl, :has_limits)
      end
    end
  end
end

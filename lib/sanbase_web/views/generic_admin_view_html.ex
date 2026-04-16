defmodule SanbaseWeb.GenericAdminHTML do
  use SanbaseWeb, :html

  use PhoenixHTMLHelpers

  embed_templates "../templates/generic_admin_html/*"
end

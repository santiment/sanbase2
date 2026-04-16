defmodule SanbaseWeb.CustomPlanHTML do
  use SanbaseWeb, :html

  import SanbaseWeb.ErrorHelpers
  use PhoenixHTMLHelpers

  embed_templates "../templates/custom_plan_html/*"
end

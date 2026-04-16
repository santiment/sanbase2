defmodule SanbaseWeb.ReportHTML do
  use SanbaseWeb, :html

  import SanbaseWeb.ErrorHelpers
  use PhoenixHTMLHelpers

  embed_templates "../templates/report_html/*"
end

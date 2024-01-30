defmodule SanbaseWeb.Layouts do
  use SanbaseWeb, :html
  import Phoenix.HTML.Link

  alias SanbaseWeb.Router.Helpers, as: Routes

  embed_templates("layouts/*")
end

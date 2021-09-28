defmodule Sanbase.StripeConfig do
  alias Sanbase.Utils.Config

  def api_key do
    Config.module_get(__MODULE__, :api_key)
  end
end

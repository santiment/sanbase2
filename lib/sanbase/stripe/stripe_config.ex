defmodule Sanbase.StripeConfig do
  require Sanbase.Utils.Config, as: Config

  def api_key do
    Config.get(:api_key)
  end
end

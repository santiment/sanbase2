defmodule Sanbase.FeatureFlag do
  require Sanbase.Utils.Config, as: Config

  def enabled?(key) do
    Config.get(key) == "true"
  end
end

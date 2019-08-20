defmodule Sanbase.FeatureFlag do
  require Sanbase.Utils.Config, as: Config

  defmacro feature_flag(key, do: block) do
    quote do
      if unquote(Config.get(key) == "true"), do: unquote(block)
    end
  end
end

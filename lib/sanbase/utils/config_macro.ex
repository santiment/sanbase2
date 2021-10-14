defmodule Sanbase.Utils.ConfigMacro do
  defmacro module_get(module, key) do
    quote bind_quoted: [module: module, key: key] do
      Application.fetch_env!(:sanbase, module)
      |> Keyword.get(key)
      |> Sanbase.Utils.Config.parse_config_value()
    end
  end
end

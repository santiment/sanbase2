defmodule Sanbase.Utils.App do
  defmacro run_in(expr, environments \\ [:dev, :prod]) do
    quote bind_quoted: [expr: expr, environments: environments] do
      require Sanbase.Utils.Config, as: Config
      env = Config.module_get(Sanbase, :environment) |> String.to_existing_atom()

      if env in environments do
        expr
      end
    end
  end
end

defmodule Sanbase.SanLang.UnboundError do
  defexception [:message]
end

defmodule Sanbase.SanLang.UndefinedFunctionError do
  defexception [:message]
end

defmodule Sanbase.SanLang.OperatorArgumentError do
  defexception [:message]
end

defmodule Sanbase.SanLang.FunctionArgumentError do
  defexception [:message]
end

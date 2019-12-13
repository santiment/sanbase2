defmodule Sanbase.Mock do
  import Mock

  for arity <- 0..10 do
    @arity arity

    def with_mock2(assert_fun, captured_fun, data)
        when is_function(captured_fun, unquote(arity)) do
      {:name, name} = Function.info(captured_fun, :name)
      {:module, module} = Function.info(captured_fun, :module)

      fun = fn unquote_splicing(Macro.generate_arguments(@arity, __MODULE__)) ->
        data
      end

      with_mock(module, [{name, fun}], do: assert_fun.())
    end
  end
end

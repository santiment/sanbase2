defmodule Sanbase.Mock do
  import Mock

  def with_mock2(assert_fun, {module, fun_name, fun_body}) do
    with_mock(module, [{fun_name, fun_body}], do: assert_fun.())
  end

  for arity <- 0..16 do
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

  def init(), do: MapSet.new()

  def prepare_mock(state \\ MapSet.new(), module, fun_name, fun_body, opts \\ [])

  def prepare_mock(state, module, fun_name, fun_body, opts)
      when is_atom(module) and is_atom(fun_name) and is_function(fun_body) do
    passthrough = if Keyword.get(opts, :passthrough, true), do: [:passthrough], else: []
    MapSet.put(state, {module, passthrough, [{fun_name, fun_body}]})
  end

  def prepare_mock2(state \\ MapSet.new(), captured_fun, data, opts \\ [])

  for arity <- 0..16 do
    @arity arity

    def prepare_mock2(state, captured_fun, data, opts)
        when is_function(captured_fun, unquote(arity)) do
      {:name, name} = Function.info(captured_fun, :name)
      {:module, module} = Function.info(captured_fun, :module)
      passthrough = if Keyword.get(opts, :passthrough) == true, do: [:passthrough], else: []

      fun = fn unquote_splicing(Macro.generate_arguments(@arity, __MODULE__)) ->
        data
      end

      MapSet.put(state, {module, passthrough, [{name, fun}]})
    end
  end

  def run_with_mocks(state, assert_fun) do
    state
    |> Enum.to_list()
    |> Enum.group_by(fn {module, opts, [{fun, _}]} -> {module, fun, opts} end)
    |> Enum.map(fn {{module, fun, opts}, list} ->
      fun_mocks =
        Enum.map(list, fn {_, _, [{_, body}]} ->
          {fun, body}
        end)

      {module, opts, fun_mocks}
    end)
    |> with_mocks(do: assert_fun.())
  end
end

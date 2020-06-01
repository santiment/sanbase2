defmodule Sanbase.Mock do
  import Mock

  @doc ~s"""
  Return a function of the specified arity that on its N-th call returns the
  result of executing the length(list) % N
  """
  def wrap_consecutives(list, opts) do
    arity = Keyword.fetch!(opts, :arity)
    cycle? = Keyword.get(opts, :cycle?, true)
    do_wrap_consecutives(list, arity, cycle?)
  end

  for arity <- 0..16 do
    @arity arity

    defp do_wrap_consecutives(list, unquote(arity), cycle?) do
      key = :rand.uniform(1_000_000_000)
      list_length = list |> length
      :persistent_term.put(key, 0)

      fn unquote_splicing(Macro.generate_arguments(@arity, __MODULE__)) ->
        position = :persistent_term.get(key)
        :persistent_term.put(key, position + 1)

        fun =
          case cycle? do
            true ->
              list |> Stream.cycle() |> Enum.at(position)

            false ->
              if(position >= list_length) do
                raise(
                  "Mocked function with wrap_consecutive is called more than #{list_length} times with `cycle?: false`"
                )
              else
                list |> Enum.at(position)
              end
          end

        fun.()
      end
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
      passthrough = if Keyword.get(opts, :passthrough, true) == true, do: [:passthrough], else: []

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

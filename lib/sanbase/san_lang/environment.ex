defmodule Sanbase.SanLang.Environment do
  defstruct env_bindings: %{}

  def new() do
    %__MODULE__{}
  end

  def put_env_bindings(%__MODULE__{} = env, bindings) do
    Map.put(env, :env_bindings, bindings)
  end

  def get_env_binding(env, key) do
    Map.get(env.env_bindings, key)
  end
end

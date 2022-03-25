defmodule Sanbase.Alert.OperationText do
  def to_template_kv(value, operation, opts \\ [])

  def to_template_kv(value, operation, opts),
    do: __MODULE__.KV.to_template_kv(value, operation, opts)

  def current_value(value, opts \\ [])

  def current_value(value, opts),
    do: __MODULE__.KV.current_value(value, opts)

  def details(type, settings, opts \\ [])

  def details(type, settings, opts),
    do: __MODULE__.KV.details(type, settings, opts)

  def merge_kvs(%{} = kv_left, %{} = kv_right) do
    Map.merge(kv_left, kv_right, fn
      :human_readable, left, right -> Enum.uniq(left ++ right)
      _, _left, right -> right
    end)
  end
end

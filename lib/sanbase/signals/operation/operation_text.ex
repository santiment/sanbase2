defmodule Sanbase.Signal.OperationText do
  def to_template_kv(value, operation, opts \\ [])

  def to_template_kv(value, operation, opts),
    do: __MODULE__.KV.to_template_kv(value, operation, opts)

  def current_value(value, opts \\ [])

  def current_value(value, opts),
    do: __MODULE__.KV.current_value(value, opts)

  def details(type, settings, opts \\ [])

  def details(type, settings, opts),
    do: __MODULE__.KV.details(type, settings, opts)
end

defmodule Sanbase.Signal.OperationText do
  @moduledoc ~s"""
  Convert values and operations to human readable text (or template and KV pairs)
  """
  def to_text(value, operation, opts \\ [])

  def to_text(value, operation, opts) do
    {template, kv} = __MODULE__.KV.to_template_kv(value, operation, opts)
    Sanbase.TemplateEngine.run(template, kv)
  end

  def to_template_kv(value, operation, opts \\ [])

  def to_template_kv(value, operation, opts),
    do: __MODULE__.KV.to_template_kv(value, operation, opts)

  def current_value(value, operation, opts \\ [])

  def current_value(value, operation, opts),
    do: __MODULE__.KV.current_value(value, operation, opts)
end

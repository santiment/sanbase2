defmodule Sanbase.Signal.OperationText do
  @moduledoc ~s"""
  A module providing a single function to_text/3 which transforms an operation
  to human readable text that can be included in the signal's payload
  """
  def to_text(value, operation, opts \\ [])

  def to_text(value, operation, opts) do
    {template, kv} = __MODULE__.KV.to_template_kv(value, operation, opts)
    Sanbase.TemplateEngine.run(template, kv)
  end

  def to_template_kv(value, operation, opts \\ [])

  def to_template_kv(value, operation, opts),
    do: __MODULE__.KV.to_template_kv(value, operation, opts)
end

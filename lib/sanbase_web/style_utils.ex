defmodule SanbaseWeb.StyleUtils do
  @moduledoc """
  Helpers for safely interpolating values into inline `style="..."` attributes.

  HEEx escapes attribute *values* but it does not parse the contents of a
  `style` string, so anything containing `;` or unbalanced delimiters can
  inject extra declarations. Run untrusted CSS lengths through
  `safe_css_length/2` before interpolating.
  """

  @css_length ~r/^\d+(\.\d+)?(px|rem|em|%|vw|vh|ch)$/

  @doc """
  Returns the value if it matches an allowed CSS length token (e.g. `40rem`,
  `100%`, `860px`); otherwise returns `default`.
  """
  @spec safe_css_length(any(), String.t()) :: String.t()
  def safe_css_length(value, default) when is_binary(value) do
    if Regex.match?(@css_length, value), do: value, else: default
  end

  def safe_css_length(_value, default), do: default
end

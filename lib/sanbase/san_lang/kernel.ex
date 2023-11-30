defmodule Sanbase.SanLang.Kernel do
  def pow(base, pow) when is_number(base) and is_number(pow) do
    base ** pow
  end

  def map(enum, fun) do
    Enum.map(enum, fun)
  end
end

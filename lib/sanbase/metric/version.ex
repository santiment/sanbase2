defmodule Sanbase.Metric.Version do
  @moduledoc ~s"""
  Classifies a canonical metric version (`"1.0"`, `"2.1"`, `"2.1.2"`) into the
  access bucket that decides which plans may request it.

    * `:base` - major version `1`. Available to every plan.
    * `:standard` - second component is `0` (`2.0`, `3.0`, ...). A newer
      computation of the metric.
    * `:pit` - second component is non-zero (`2.1`, `2.1.1`, `3.1`, ...). The
      point-in-time variant of a computation family. Point releases of a PIT
      variant stay in the same bucket, so access to `2.1` carries over to `2.1.1`.

  Anything that is not a dotted number (for example `Experimental (Weighted Age)`)
  is `:other`. Experimental versions have their own alpha-only rule; any other
  non-numeric version is treated as the most restricted bucket by the callers.

  The classification is derived from the string alone, so a new version family
  needs no code change.
  """

  @type bucket :: :base | :standard | :pit | :other

  @spec classify(String.t()) :: bucket
  def classify(version) when is_binary(version) do
    case version |> String.split(".") |> Enum.map(&Integer.parse/1) do
      [{1, ""} | rest] -> if valid_rest?(rest), do: :base, else: :other
      [{_major, ""}, {0, ""} | rest] -> if valid_rest?(rest), do: :standard, else: :other
      [{_major, ""}, {_minor, ""} | rest] -> if valid_rest?(rest), do: :pit, else: :other
      _ -> :other
    end
  end

  def classify(_), do: :other

  defp valid_rest?(rest), do: Enum.all?(rest, &match?({_, ""}, &1))
end

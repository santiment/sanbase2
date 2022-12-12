defmodule Sanbase.Clickhouse.Label.Validator do
  @doc ~s"""
  Check if the provided label_fqn is valid
  """
  @spec valid_label_fqn?(String.t()) :: true | {:error, String.t()}
  def valid_label_fqn?(label_fqn) do
    with [owner, key_value, version] <- parse_label_fqn(label_fqn),
         true <- valid_owner?(owner, label_fqn),
         true <- valid_key_value?(key_value, label_fqn),
         true <- valid_version?(version, label_fqn) do
      true
    end
  end

  defp parse_label_fqn(label_fqn) do
    case String.split(label_fqn, ["/", ":"]) do
      [owner, key_value, version] -> [owner, key_value, version]
      _ -> {:error, "The label_fqn '#{label_fqn}' is malformed."}
    end
  end

  defp valid_owner?(owner, label_fqn) do
    case is_binary(owner) and ascii_string_or_nil?(owner) do
      true -> true
      false -> {:error, error_msg(:owner, owner, label_fqn)}
    end
  end

  defp ascii_string_or_nil?(nil), do: false

  defp ascii_string_or_nil?(binary) when is_binary(binary) do
    binary
    |> String.to_charlist()
    |> List.ascii_printable?()
  end

  defp valid_key_value?(key_value, label_fqn) do
    case String.split(key_value, "->") do
      [key, value] ->
        with true <- valid_key?(key, label_fqn),
             true <- valid_value?(value, label_fqn) do
          true
        end

      [key] ->
        valid_key?(key, label_fqn)
    end
  end

  defp valid_key?(key, label_fqn) do
    case Regex.match?(~r/[a-zA-Z0-0\(\)\_\-]+/, key) do
      true -> true
      false -> {:error, error_msg(:key, key, label_fqn)}
    end
  end

  defp valid_value?(value, label_fqn) do
    case Regex.match?(~r/[a-zA-Z0-0\(\)\_\-\s\:\/]+/, value) do
      true -> true
      false -> {:error, error_msg(:value, value, label_fqn)}
    end
  end

  defp valid_version?("latest", _label_fqn), do: true

  defp valid_version?("v" <> version_number = version, label_fqn) do
    case Integer.parse(version_number) do
      {_num, ""} -> true
      _ -> {:error, error_msg(:version, version, label_fqn)}
    end
  end

  defp valid_version?(version, label_fqn),
    do: {:error, error_msg(:version, version, label_fqn)}

  defp error_msg(key, value, label_fqn) do
    "The #{key} part '#{inspect(value)}' of the label_fqn '#{inspect(label_fqn)}' is not valid."
  end
end

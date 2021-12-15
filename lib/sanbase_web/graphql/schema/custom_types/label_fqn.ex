defmodule SanbaseWeb.Graphql.CustomTypes.LabelFqn do
  @moduledoc """
  The interval scalar type allows arbitrary interval values to be passed in and out.
  """
  use Absinthe.Schema.Notation

  scalar :interval_or_now, name: "interval_or_now" do
    description("""
    The input is either a valid `interval` type or the string `now`
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}

  defp decode(%Absinthe.Blueprint.Input.String{value: label_fqn}) do
    with [owner, rest] <- String.split(label_fqn, "/"),
         true <- is_valid_owner?(owner, label_fqn),
         [key, rest] <- String.split(rest, "->"),
         true <- is_valid_key?(key, label_fqn),
         [value, version] <- String.split(rest, ":"),
         true <- is_valid_value?(value, label_fqn),
         true <- is_valid_version?(version, label_fqn) do
      {:ok, value}
    end
  end

  defp decode(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp decode(_) do
    :error
  end

  defp encode(value), do: value

  defp is_valid_owner?(owner, label_fqn) do
    case is_binary(owner) and Sanbase.Accounts.User.ascii_string_or_nil?(owner) do
      true ->
        true

      false ->
        {:error,
         "The owner part '#{inspect(owner)} ' of the label_fqn '#{inspect(label_fqn)}' is not valid."}
    end
  end

  defp is_valid_key?(key, label_fqn) do
    case Regex.match?(~r/[a-zA-Z0-0\(\)]+/, key) do
      true ->
        true

      false ->
        {:error,
         "The key part '#{inspect(key)} ' of the label_fqn '#{inspect(label_fqn)}' is not valid."}
    end
  end

  defp is_valid_value?(value, label_fqn) do
    case Regex.match?(~r/[a-zA-Z0-0\(\)]+/, value) do
      true ->
        true

      false ->
        {:error,
         "The value part '#{inspect(value)} ' of the label_fqn '#{inspect(label_fqn)}' is not valid."}
    end
  end

  defp is_valid_version?("latest", _label_fqn), do: true

  defp is_valid_version?(version, label_fqn) do
    error_msg =
      "The version part '#{inspect(version)} ' of the label_fqn '#{inspect(label_fqn)}' is not valid."

    case version do
      "v" <> number ->
        case Integer.parse(number) do
          {_num, ""} -> true
          _ -> {:error, error_msg}
        end

      _ ->
        {:error, error_msg}
    end
  end
end

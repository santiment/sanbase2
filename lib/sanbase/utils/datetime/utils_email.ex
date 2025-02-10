defmodule Sanbase.Utils.Email do
  # ensure that the email looks valid
  @moduledoc false
  def valid_email?(email) when is_binary(email) do
    case Regex.run(~r/^[\w.!#$%&’*+\-\/=?\^`{|}~]+@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*$/i, email) do
      nil ->
        false

      [_email] ->
        true
    end
  end

  def valid_email?(_), do: false
end

defmodule Sanbase.Utils.Email do
  # Looks like an email and gen_smtp can parse it as a single bare "To" address
  def valid_email?(email) when is_binary(email) do
    Regex.match?(~r/^[\w.!#$%&’*+\-\/=?\^`{|}~]+@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*$/i, email) and
      :smtp_util.parse_rfc5322_addresses(email) ==
        {:ok, [{:undefined, String.to_charlist(email)}]}
  end

  def valid_email?(_), do: false
end

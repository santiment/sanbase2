defmodule Sanbase.BlockchainAddress.ListSelector do
  defdelegate valid_selector?(args), to: __MODULE__.Validator

  def addresses(%{selector: selector}), do: evaluate_selector(selector)

  defp evaluate_selector(%{name: "top_addresses", args: %{slug: slug, limit: limit}}) do
    Sanbase.Balance.current_balance_top_addresses(slug, 1, limit, :desc)
  end

  defp evaluate_selector(selector) do
    {:error, "Invalid selector: #{inspect(selector)}"}
  end
end

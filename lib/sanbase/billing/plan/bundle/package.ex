defmodule Sanbase.Billing.Plan.Bundle.Package do
  @moduledoc ~s"""
  The five data packages that can be bought, and the rule that says what each
  one contains.

  A package is defined as a **rule** - "everything in the Market category" - not
  as a hand-written metric list. The list is worked out from the rule by
  `Sanbase.Billing.Plan.Bundle.PackageSnapshot`, which freezes the result so that
  editing categorization does not change what existing customers already paid
  for. See §5 and task PD in `docs/composable-api-plans-handover.md`.

  ## Why the category name and not the id

  Category ids differ between environments, so a definition keyed on ids would
  be wrong somewhere. Names are stable and are what the Notion task uses. The
  cost is that a rename silently empties a package, which is why
  `PackageSnapshot` refuses to build when a named category is missing rather than
  producing an empty list.

  ## Excluded from every package

  Deprecated and hidden metrics are never sold, even when they sit in a sold
  category (§6.1). Existing customers of *other* plans keep them - this only
  governs what a package grants.
  """

  @type slug :: String.t()

  @type t :: %{
          slug: slug(),
          name: String.t(),
          category: String.t()
        }

  # The order is the order they are offered in.
  @packages [
    %{slug: "market", name: "Market Data", category: "Market"},
    %{slug: "development", name: "Development Data", category: "Development"},
    %{slug: "social", name: "Social Sentiment", category: "Social"},
    %{slug: "onchain_core", name: "On-chain (Core)", category: "On-chain"},
    %{slug: "onchain_labels", name: "On-chain Labels", category: "On-chain Labels"}
  ]

  @slugs Enum.map(@packages, & &1.slug)

  @doc ~s"""
  Every package definition, in the order they are offered.
  """
  @spec all() :: [t()]
  def all, do: @packages

  @doc ~s"""
  The slugs of all packages. These are the values stored in
  `subscription_items.sku` and in an entitlement's `packages` list.
  """
  @spec slugs() :: [slug()]
  def slugs, do: @slugs

  @doc ~s"""
  Whether the given string names a package that is sold.
  """
  @spec valid_slug?(term()) :: boolean()
  def valid_slug?(slug) when is_binary(slug), do: slug in @slugs
  def valid_slug?(_), do: false

  @doc ~s"""
  The package with this slug.
  """
  @spec by_slug(term()) :: {:ok, t()} | {:error, String.t()}
  def by_slug(slug) when is_binary(slug) do
    case Enum.find(@packages, &(&1.slug == slug)) do
      nil ->
        {:error, "Unknown package #{inspect(slug)}. Known packages: #{Enum.join(@slugs, ", ")}."}

      package ->
        {:ok, package}
    end
  end

  def by_slug(slug), do: {:error, "Package slug must be a string, got #{inspect(slug)}."}
end

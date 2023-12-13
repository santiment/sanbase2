defmodule Sanbase.Billing.Plan.PurchasingPowerParity do
  @moduledoc """
  Module for managing Purchasing Power Parity plans (PPP).
  """

  alias Sanbase.Billing.Plan
  alias Sanbase.Geoip.Data

  @plans %{
    off_70_percent: [206, 207, 208, 209]
  }

  @country_plan_map %{
    "TR" => :off_70_percent
  }

  @symbol_to_percent_map %{
    off_70_percent: 70
  }

  def plans(), do: @plans
  def country_plan_map(), do: @country_plan_map
  def symbol_to_percent_map(), do: @symbol_to_percent_map

  def plans_for_country(nil), do: []

  def plans_for_country(country_code) do
    case Map.get(@country_plan_map, country_code) do
      nil -> []
      key -> @plans[key] |> Plan.by_ids()
    end
  end

  def ip_eligible_for_ppp?(ip_address) do
    case Data.find_or_insert(ip_address) do
      {:ok, geoip_data} ->
        # Turkey
        country_eligible_for_ppp?(geoip_data)

      _ ->
        false
    end
  end

  def country_eligible_for_ppp?(geoip_data) do
    geoip_data.country_code in ["TR"] and geoip_data.is_vpn == false
  end

  # Purchasing power parity settings.
  def ppp_settings(geoip_data) do
    percent_symbol = @country_plan_map |> Map.get(geoip_data.country_code)
    percent_off = @symbol_to_percent_map |> Map.get(percent_symbol)

    plans_for_country = plans_for_country(geoip_data.country_code)

    %{
      is_eligible_for_ppp: true,
      plans: plans_for_country,
      country: geoip_data.country_name,
      percent_off: percent_off
    }
  end
end

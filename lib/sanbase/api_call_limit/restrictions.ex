defmodule Sanbase.ApiCallLimit.Restrictions do
  def call_limits_per_month() do
    %{
      "sanbase_basic" => 1000,
      "sanbase_pro" => 5000,
      "sanbase_pro_plus" => 80_000,
      "sanbase_max" => 80_000,
      "sanapi_free" => 1000,
      "sanapi_basic" => 300_000,
      "sanapi_pro" => 600_000,
      "sanapi_business_pro" => 600_000,
      "sanapi_business_max" => 1_200_000
    }
  end

  def call_limits_per_hour() do
    %{
      "sanbase_basic" => 500,
      "sanbase_pro" => 1000,
      "sanbase_pro_plus" => 4000,
      "sanbase_max" => 4000,
      "sanapi_free" => 500,
      "sanapi_basic" => 20_000,
      "sanapi_pro" => 30_000,
      "sanapi_business_pro" => 30_000,
      "sanapi_business_max" => 60_000
    }
  end

  def call_limits_per_minute() do
    %{
      "sanbase_basic" => 100,
      "sanbase_pro" => 100,
      "sanbase_pro_plus" => 100,
      "sanbase_max" => 100,
      "sanapi_free" => 100,
      "sanapi_basic" => 300,
      "sanapi_pro" => 600,
      "sanapi_business_pro" => 600,
      "sanapi_business_max" => 1200
    }
  end

  def response_size_limits_mb_per_month() do
    # TODO: After gathering enough statistics of actual usage update these
    # values
    %{
      "sanbase_basic" => 1000,
      "sanbase_pro" => 2000,
      "sanbase_pro_plus" => 12_000,
      "sanbase_max" => 20_000,
      "sanapi_free" => 1000,
      "sanapi_basic" => 20_000,
      "sanapi_pro" => 40_000,
      "sanapi_business_pro" => 50_000,
      "sanapi_business_max" => 100_000
    }
  end
end

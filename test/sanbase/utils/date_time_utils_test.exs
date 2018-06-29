defmodule Sanbase.DateTimeUtilsTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.DateTimeUtils

  test "#compound_duration_to_seconds/1" do
    assert DateTimeUtils.compound_duration_to_seconds("10000000000ns") == 10
    assert DateTimeUtils.compound_duration_to_seconds("100s") == 100
    assert DateTimeUtils.compound_duration_to_seconds("1m") == 60
    assert DateTimeUtils.compound_duration_to_seconds("1h") == 3600
    assert DateTimeUtils.compound_duration_to_seconds("1d") == 86400
    assert DateTimeUtils.compound_duration_to_seconds("1w") == 604_800
    assert DateTimeUtils.compound_duration_to_seconds("100") == 100
  end
end

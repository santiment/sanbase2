defmodule Sanbase.SimpleMailerTest do
  use Sanbase.DataCase, async: false

  import Mock

  @moduletag capture_log: true

  test "send_email/3 returns an error tuple when the delivery exits" do
    with_mock Swoosh.Adapters.AmazonSES,
      validate_config: fn _config -> :ok end,
      deliver: fn _email, _config -> exit(:boom) end do
      assert Sanbase.SimpleMailer.send_email("user@santiment.net", "Subject", "Body") ==
               {:error, :boom}
    end
  end
end

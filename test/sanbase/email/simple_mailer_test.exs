defmodule Sanbase.SimpleMailerTest do
  use Sanbase.DataCase, async: false

  import Mock

  @moduletag capture_log: true

  for recipient <- ["", "foo.@bar.com"] do
    test "send_email/3 does not send to the malformed recipient #{inspect(recipient)}" do
      with_mock Swoosh.Adapters.AmazonSES,
        validate_config: fn _config -> :ok end,
        deliver: fn _email, _config -> {:ok, %{id: "mocked-message-id"}} end do
        assert Sanbase.SimpleMailer.send_email(unquote(recipient), "Subject", "Body") ==
                 {:error, :invalid_email}

        assert_not_called(Swoosh.Adapters.AmazonSES.deliver(:_, :_))
      end
    end
  end

  test "send_email/3 returns an error tuple when the delivery exits" do
    with_mock Swoosh.Adapters.AmazonSES,
      validate_config: fn _config -> :ok end,
      deliver: fn _email, _config -> exit(:boom) end do
      assert Sanbase.SimpleMailer.send_email("user@santiment.net", "Subject", "Body") ==
               {:error, :boom}
    end
  end
end

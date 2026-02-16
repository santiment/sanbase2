defmodule SanbaseWeb.SESControllerTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  alias Sanbase.Email.SesEmailEvent

  @secret "test_webhook_secret_123"

  setup do
    Application.put_env(:sanbase, :ses_webhook_secret, @secret)

    on_exit(fn ->
      Application.delete_env(:sanbase, :ses_webhook_secret)
    end)

    :ok
  end

  describe "webhook/2 - authentication" do
    test "rejects requests with invalid secret", %{conn: conn} do
      conn = post(conn, ~p"/ses/webhook/wrong_secret", %{"Type" => "Notification"})
      assert response(conn, 403) == "Forbidden"
    end

    test "rejects requests when no secret is configured", %{conn: conn} do
      Application.delete_env(:sanbase, :ses_webhook_secret)

      conn = post(conn, ~p"/ses/webhook/any_secret", %{"Type" => "Notification"})
      assert response(conn, 403) == "Forbidden"
    end

    test "accepts requests with valid secret", %{conn: conn} do
      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "Notification",
          "Message" => Jason.encode!(%{"eventType" => "Unknown"})
        })

      assert response(conn, 200) == ""
    end
  end

  describe "webhook/2 - bounce events" do
    test "stores bounce event", %{conn: conn} do
      ses_event = %{
        "eventType" => "Bounce",
        "bounce" => %{
          "bounceType" => "Permanent",
          "bounceSubType" => "General",
          "bouncedRecipients" => [
            %{"emailAddress" => "bounced@example.com", "status" => "5.1.1"}
          ],
          "timestamp" => "2026-02-16T10:00:00.000Z"
        },
        "mail" => %{
          "messageId" => "ses-bounce-msg-001",
          "destination" => ["bounced@example.com"]
        }
      }

      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "Notification",
          "Message" => Jason.encode!(ses_event)
        })

      assert response(conn, 200) == ""

      events = SesEmailEvent.list_events(email_search: "bounced@example.com")
      assert length(events) == 1

      event = hd(events)
      assert event.event_type == "Bounce"
      assert event.bounce_type == "Permanent"
      assert event.bounce_sub_type == "General"
      assert event.message_id == "ses-bounce-msg-001"
    end

    test "does not add to exclusion list", %{conn: conn} do
      ses_event = %{
        "eventType" => "Bounce",
        "bounce" => %{
          "bounceType" => "Permanent",
          "bounceSubType" => "General",
          "bouncedRecipients" => [
            %{"emailAddress" => "hard-bounced@example.com"}
          ],
          "timestamp" => "2026-02-16T10:00:00.000Z"
        },
        "mail" => %{"messageId" => "ses-msg-002"}
      }

      post(conn, ~p"/ses/webhook/#{@secret}", %{
        "Type" => "Notification",
        "Message" => Jason.encode!(ses_event)
      })

      refute Sanbase.Email.email_excluded?("hard-bounced@example.com")
    end
  end

  describe "webhook/2 - complaint events" do
    test "stores complaint event", %{conn: conn} do
      ses_event = %{
        "eventType" => "Complaint",
        "complaint" => %{
          "complainedRecipients" => [
            %{"emailAddress" => "complainer@example.com"}
          ],
          "complaintFeedbackType" => "abuse",
          "timestamp" => "2026-02-16T10:00:00.000Z"
        },
        "mail" => %{"messageId" => "ses-complaint-msg-001"}
      }

      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "Notification",
          "Message" => Jason.encode!(ses_event)
        })

      assert response(conn, 200) == ""

      events = SesEmailEvent.list_events(email_search: "complainer@example.com")
      assert length(events) == 1

      event = hd(events)
      assert event.event_type == "Complaint"
      assert event.complaint_feedback_type == "abuse"
    end

    test "does not add complaints to exclusion list", %{conn: conn} do
      ses_event = %{
        "eventType" => "Complaint",
        "complaint" => %{
          "complainedRecipients" => [%{"emailAddress" => "spam-report@example.com"}],
          "complaintFeedbackType" => "abuse",
          "timestamp" => "2026-02-16T10:00:00.000Z"
        },
        "mail" => %{"messageId" => "ses-msg-003"}
      }

      post(conn, ~p"/ses/webhook/#{@secret}", %{
        "Type" => "Notification",
        "Message" => Jason.encode!(ses_event)
      })

      refute Sanbase.Email.email_excluded?("spam-report@example.com")
    end
  end

  describe "webhook/2 - delivery events" do
    test "stores delivery event", %{conn: conn} do
      ses_event = %{
        "eventType" => "Delivery",
        "delivery" => %{
          "recipients" => ["delivered@example.com"],
          "timestamp" => "2026-02-16T10:00:00.000Z",
          "smtpResponse" => "250 2.0.0 OK"
        },
        "mail" => %{"messageId" => "ses-delivery-msg-001"}
      }

      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "Notification",
          "Message" => Jason.encode!(ses_event)
        })

      assert response(conn, 200) == ""

      events = SesEmailEvent.list_events(email_search: "delivered@example.com")
      assert length(events) == 1

      event = hd(events)
      assert event.event_type == "Delivery"
      assert event.smtp_response == "250 2.0.0 OK"
    end
  end

  describe "webhook/2 - send events" do
    test "stores send event", %{conn: conn} do
      ses_event = %{
        "eventType" => "Send",
        "send" => %{},
        "mail" => %{
          "messageId" => "ses-send-msg-001",
          "destination" => ["sent@example.com"],
          "timestamp" => "2026-02-16T10:00:00.000Z"
        }
      }

      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "Notification",
          "Message" => Jason.encode!(ses_event)
        })

      assert response(conn, 200) == ""

      events = SesEmailEvent.list_events(email_search: "sent@example.com")
      assert length(events) == 1
      assert hd(events).event_type == "Send"
    end
  end

  describe "webhook/2 - reject events" do
    test "stores reject event", %{conn: conn} do
      ses_event = %{
        "eventType" => "Reject",
        "reject" => %{"reason" => "VIRUS"},
        "mail" => %{
          "messageId" => "ses-reject-msg-001",
          "destination" => ["rejected@example.com"],
          "timestamp" => "2026-02-16T10:00:00.000Z"
        }
      }

      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "Notification",
          "Message" => Jason.encode!(ses_event)
        })

      assert response(conn, 200) == ""

      events = SesEmailEvent.list_events(email_search: "rejected@example.com")
      assert length(events) == 1

      event = hd(events)
      assert event.event_type == "Reject"
      assert event.reject_reason == "VIRUS"
    end
  end

  describe "webhook/2 - delivery delay events" do
    test "stores delivery delay event", %{conn: conn} do
      ses_event = %{
        "eventType" => "DeliveryDelay",
        "deliveryDelay" => %{
          "delayType" => "InternalFailure",
          "delayedRecipients" => [
            %{"emailAddress" => "delayed@example.com", "status" => "4.4.1"}
          ],
          "timestamp" => "2026-02-16T10:00:00.000Z"
        },
        "mail" => %{"messageId" => "ses-delay-msg-001"}
      }

      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "Notification",
          "Message" => Jason.encode!(ses_event)
        })

      assert response(conn, 200) == ""

      events = SesEmailEvent.list_events(email_search: "delayed@example.com")
      assert length(events) == 1

      event = hd(events)
      assert event.event_type == "DeliveryDelay"
      assert event.delay_type == "InternalFailure"
    end
  end

  describe "webhook/2 - multiple recipients" do
    test "stores events for each bounced recipient", %{conn: conn} do
      ses_event = %{
        "eventType" => "Bounce",
        "bounce" => %{
          "bounceType" => "Transient",
          "bounceSubType" => "MailboxFull",
          "bouncedRecipients" => [
            %{"emailAddress" => "user1@example.com"},
            %{"emailAddress" => "user2@example.com"}
          ],
          "timestamp" => "2026-02-16T10:00:00.000Z"
        },
        "mail" => %{"messageId" => "ses-multi-msg-001"}
      }

      post(conn, ~p"/ses/webhook/#{@secret}", %{
        "Type" => "Notification",
        "Message" => Jason.encode!(ses_event)
      })

      assert SesEmailEvent.count_events(event_type: "Bounce") == 2
    end
  end

  describe "webhook/2 - SNS message types" do
    test "returns 200 for unknown SNS message types", %{conn: conn} do
      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "UnsubscribeConfirmation"
        })

      assert response(conn, 200) == ""
    end

    test "handles already-parsed Message (map instead of string)", %{conn: conn} do
      conn =
        post(conn, ~p"/ses/webhook/#{@secret}", %{
          "Type" => "Notification",
          "Message" => %{
            "eventType" => "Send",
            "send" => %{},
            "mail" => %{
              "messageId" => "ses-parsed-msg",
              "destination" => ["parsed@example.com"],
              "timestamp" => "2026-02-16T10:00:00.000Z"
            }
          }
        })

      assert response(conn, 200) == ""

      events = SesEmailEvent.list_events(email_search: "parsed@example.com")
      assert length(events) == 1
    end
  end
end

defmodule SanbaseWeb.ScheduledDeprecationLiveTest do
  use SanbaseWeb.ConnCase, async: true
  use Oban.Testing, repo: Sanbase.Repo

  import Phoenix.LiveViewTest
  import Mock
  import Sanbase.Factory

  alias Sanbase.Notifications
  alias Sanbase.Workers.SendDeprecationEmailWorker

  describe "scheduled deprecation form" do
    setup do
      user = insert(:user)
      admin_role = insert(:role_admin_panel_viewer)
      Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
      {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
      conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
      {:ok, conn: conn, user: user}
    end

    test "shows validation errors for invalid date", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      invalid_date = Date.utc_today() |> Date.add(2) |> Date.to_iso8601()

      invalid_form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => invalid_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => "https://academy.santiment.net/alternative-endpoint"
          }
        }
      }

      rendered = view |> form("#deprecation-form", invalid_form_data) |> render_submit()
      assert rendered =~ "Please correct the errors below"
      assert rendered =~ "Deprecation date must be at least 5 days in the future"
    end

    test "shows validation errors for invalid URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      invalid_url_form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => future_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => "invalid-url,https://academy.santiment.net"
          }
        }
      }

      rendered = view |> form("#deprecation-form", invalid_url_form_data) |> render_submit()
      assert rendered =~ "Please correct the errors below"
      assert rendered =~ "Invalid URL"
    end

    test "shows preview when valid data is entered", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      valid_partial_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => future_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => "https://academy.santiment.net/alternative-endpoint"
          }
        }
      }

      rendered = view |> form("#deprecation-form", valid_partial_data) |> render_change()
      assert rendered =~ "Preview Details"
      assert rendered =~ "get_metric"
    end

    test "shows custom subjects in preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      custom_subjects_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => future_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => "https://academy.santiment.net/alternative-endpoint",
            "schedule" => %{"subject" => "Custom Schedule Subject"},
            "reminder" => %{"subject" => "Custom Reminder Subject"},
            "executed" => %{"subject" => "Custom Executed Subject"}
          }
        }
      }

      rendered = view |> form("#deprecation-form", custom_subjects_data) |> render_change()
      assert rendered =~ "Custom Schedule Subject"
    end

    test "creates notification and schedules jobs on valid submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => future_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" =>
              "https://academy.santiment.net/alternative-endpoint,https://api.santiment.net/graphql",
            "schedule" => %{"subject" => "Custom Schedule Subject for get_metric"},
            "reminder" => %{"subject" => "Custom Reminder Subject for get_metric"},
            "executed" => %{"subject" => "Custom Executed Subject for get_metric"}
          }
        }
      }

      rendered = view |> form("#deprecation-form", form_data) |> render_submit()
      assert rendered =~ "Deprecation notification scheduled successfully!"
      assert rendered =~ "Schedule API Endpoint Deprecation Notification"
      refute rendered =~ "get_metric"
      refute rendered =~ "Preview Details"

      notifications = Notifications.list_scheduled_deprecations()
      assert length(notifications) == 1
      notification = List.first(notifications)
      assert notification.api_endpoint == "get_metric"
      assert notification.contact_list_name == "API Users Only"
      assert notification.deprecation_date == Date.from_iso8601!(future_date)
      assert notification.status == "active"

      assert notification.links == [
               "https://academy.santiment.net/alternative-endpoint",
               "https://api.santiment.net/graphql"
             ]

      assert notification.schedule_email_job_id != nil
      assert notification.reminder_email_job_id != nil
      assert notification.executed_email_job_id != nil
      assert notification.schedule_email_subject == "Custom Schedule Subject for get_metric"
      assert notification.reminder_email_subject == "Custom Reminder Subject for get_metric"
      assert notification.executed_email_subject == "Custom Executed Subject for get_metric"
      assert notification.schedule_email_html =~ "get_metric"
      assert notification.reminder_email_html =~ "get_metric"
      assert notification.executed_email_html =~ "get_metric"
      assert notification.schedule_email_scheduled_at != nil
      assert notification.reminder_email_scheduled_at != nil
      assert notification.executed_email_scheduled_at != nil
      reminder_date = notification.reminder_email_scheduled_at |> DateTime.to_date()
      expected_reminder_date = notification.deprecation_date |> Date.add(-3)
      assert reminder_date == expected_reminder_date
      executed_date = notification.executed_email_scheduled_at |> DateTime.to_date()
      assert executed_date == notification.deprecation_date

      schedule_job =
        all_enqueued(
          worker: SendDeprecationEmailWorker,
          args: %{notification_id: notification.id, email_type: "schedule"}
        )

      assert length(schedule_job) == 1

      assert Enum.at(schedule_job, 0).scheduled_at <=
               DateTime.utc_now() |> DateTime.add(3600, :second)

      reminder_job =
        all_enqueued(
          worker: SendDeprecationEmailWorker,
          args: %{notification_id: notification.id, email_type: "reminder"}
        )

      assert length(reminder_job) == 1
      assert DateTime.to_date(Enum.at(reminder_job, 0).scheduled_at) == expected_reminder_date

      executed_job =
        all_enqueued(
          worker: SendDeprecationEmailWorker,
          args: %{notification_id: notification.id, email_type: "executed"}
        )

      assert length(executed_job) == 1

      assert DateTime.to_date(Enum.at(executed_job, 0).scheduled_at) ==
               notification.deprecation_date

      assert_enqueued(
        worker: SendDeprecationEmailWorker,
        args: %{notification_id: notification.id, email_type: "schedule"}
      )

      assert_enqueued(
        worker: SendDeprecationEmailWorker,
        args: %{notification_id: notification.id, email_type: "reminder"}
      )

      assert_enqueued(
        worker: SendDeprecationEmailWorker,
        args: %{notification_id: notification.id, email_type: "executed"}
      )
    end

    test "handles Oban job scheduling errors gracefully", %{conn: conn} do
      # Using with_mock instead of Oban.Testing.stub_global which is private
      with_mock(Oban, [],
        insert: fn _oban_config, _job -> {:error, "Failed to schedule job"} end
      ) do
        # Connect to the LiveView with the correct path
        {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")

        # Get future date for the deprecation
        future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

        # Fill in the form with valid data
        form_data = %{
          "deprecation" => %{
            "data" => %{
              "scheduled_at" => future_date,
              "contact_list" => "API Users Only",
              "api_endpoint" => "get_metric",
              "links" => "https://academy.santiment.net/alternative-endpoint"
            }
          }
        }

        # Submit the form
        rendered =
          view
          |> form("#deprecation-form", form_data)
          |> render_submit()

        # Assert error message appears
        assert rendered =~ "Failed to schedule deprecation"

        # Verify no record was created
        notifications = Notifications.list_scheduled_deprecations()
        assert Enum.empty?(notifications)
      end
    end

    test "form is reset after successful submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => future_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => "https://academy.santiment.net/alternative-endpoint"
          }
        }
      }

      rendered = view |> form("#deprecation-form", form_data) |> render_submit()
      assert rendered =~ "Deprecation notification scheduled successfully!"
      # After success, form should be reset (no preview, no old values)
      assert rendered =~ "Schedule API Endpoint Deprecation Notification"
      refute rendered =~ "get_metric"
      refute rendered =~ "Preview Details"
    end

    test "does not show preview if required fields are missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")

      form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => "",
            "contact_list" => "API Users Only",
            "api_endpoint" => "",
            "links" => ""
          }
        }
      }

      rendered = view |> form("#deprecation-form", form_data) |> render_change()
      refute rendered =~ "Preview Details"
    end

    test "shows validation errors when required fields are missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")

      form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => "",
            "contact_list" => "API Users Only",
            "api_endpoint" => "",
            "links" => ""
          }
        }
      }

      rendered = view |> form("#deprecation-form", form_data) |> render_submit()
      assert rendered =~ "Please correct the errors below"
      assert rendered =~ "cannot be blank"
    end

    test "accepts empty links field", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => future_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => ""
          }
        }
      }

      rendered = view |> form("#deprecation-form", form_data) |> render_submit()
      assert rendered =~ "Deprecation notification scheduled successfully!"
      notification = List.first(Notifications.list_scheduled_deprecations())
      assert notification.links == []
    end

    test "shows error for invalid date format", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")

      form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => "not-a-date",
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => ""
          }
        }
      }

      rendered = view |> form("#deprecation-form", form_data) |> render_submit()
      assert rendered =~ "is not a valid date"
    end

    test "accepts links field with only commas as empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => future_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => ",,,"
          }
        }
      }

      rendered = view |> form("#deprecation-form", form_data) |> render_submit()
      assert rendered =~ "Deprecation notification scheduled successfully!"
      notification = List.first(Notifications.list_scheduled_deprecations())
      assert notification.links == []
    end

    test "renders custom subject with template variable", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/scheduled_deprecations/new")
      future_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      form_data = %{
        "deprecation" => %{
          "data" => %{
            "scheduled_at" => future_date,
            "contact_list" => "API Users Only",
            "api_endpoint" => "get_metric",
            "links" => "",
            "schedule" => %{"subject" => "Deprecation for {{api_endpoint}}"}
          }
        }
      }

      rendered = view |> form("#deprecation-form", form_data) |> render_change()
      assert rendered =~ "Deprecation for get_metric"
    end
  end
end

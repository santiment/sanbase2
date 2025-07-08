defmodule SanbaseWeb.AcademyQALiveTest do
  use SanbaseWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import SanbaseWeb.AcademyQAComponents
  import Sanbase.Factory

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
    {:ok, conn: conn, user: user}
  end

  describe "Academy Q&A Live View" do
    test "mounts successfully and displays initial elements", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/academy_qa")

      assert html =~ "Academy Q&amp;A"
      assert html =~ "Ask questions about Santiment"
      assert html =~ "Ask a question about Santiment..."
      assert html =~ "Ask"
    end

    test "displays error for empty question", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/academy_qa")

      html = render_submit(view, "ask_question", %{question: ""})

      assert html =~ "Please enter a question"
    end

    test "clears question and results", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/academy_qa")

      # Set a question first by submitting it
      render_submit(view, "ask_question", %{question: "What is Santiment?"})

      # Clear the question
      html = render_click(view, "clear_question")

      refute html =~ "What is Santiment?"
    end
  end

  describe "Academy Q&A Components" do
    test "academy_header renders correctly" do
      assigns = %{title: "Test Academy"}

      html =
        render_component(&academy_header/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "Test Academy"
      assert html =~ "Ask questions about Santiment"
    end

    test "question_form renders with correct elements" do
      assigns = %{question: "Test question", loading: false}

      html =
        render_component(&question_form/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "Test question"
      assert html =~ "Ask a question about Santiment..."
      assert html =~ "Ask"
      assert html =~ "Clear"
    end

    test "question_form shows loading state" do
      assigns = %{question: "Test question", loading: true}

      html =
        render_component(&question_form/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "Asking..."
      assert html =~ "disabled"
    end

    test "suggestions_section renders suggestions correctly" do
      suggestions = [
        "What is Santiment?",
        "How does SAN token work?",
        "What are the subscription plans?"
      ]

      assigns = %{
        suggestions: suggestions,
        suggestions_confidence: "high"
      }

      html =
        render_component(&suggestions_section/1, assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "Related Questions"
      assert html =~ "HIGH CONFIDENCE"
      assert html =~ "What is Santiment?"
      assert html =~ "How does SAN token work?"
      assert html =~ "What are the subscription plans?"
      assert html =~ "ask_suggestion"
    end
  end
end

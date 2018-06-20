defmodule SanbaseWeb.Graphql.PrivacyPolicyAccessTest do
  use SanbaseWeb.ConnCase

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{salt: User.generate_salt()}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn}
  end

  test "access is restricted when privacy policy is not accepted", %{conn: conn} do
    new_email = "test@test.test"

    mutation = """
    mutation {
      changeEmail(email: "#{new_email}") {
        email
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(mutation))

    [errors] = json_response(result, 200)["errors"]

    assert errors["message"] =~ "Access denied"
    assert errors["message"] =~ "Accept the privacy policy to activate your account"
  end

  test "access is regained after accepting the privacy policy", %{conn: conn} do
    # First update the terms and conditions
    update_mutation = """
    mutation {
      updateTermsAndConditions(
        privacyPolicyAccepted: true,
        marketingAccepted: false){
          id,
          privacyPolicyAccepted
        }
    }
    """

    conn |> post("/graphql", mutation_skeleton(update_mutation))

    # Try to change the email now
    new_email = "test@test.test"

    mutation = """
    mutation {
      changeEmail(email: "#{new_email}") {
        email
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(mutation))

    assert json_response(result, 200)["data"]["changeEmail"]["email"] == new_email
  end
end

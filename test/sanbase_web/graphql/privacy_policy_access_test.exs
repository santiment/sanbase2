defmodule SanbaseWeb.Graphql.PrivacyPolicyAccessTest do
  use SanbaseWeb.ConnCase, async: false

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

  test "can update only a single privacy policy", %{conn: conn} do
    # Accept the privacy policy
    update_mutation1 = """
    mutation {
      updateTermsAndConditions(
        privacyPolicyAccepted: true){
          id
        }
    }
    """

    conn |> post("/graphql", mutation_skeleton(update_mutation1))

    # Update the marketing policy, privacy policy will stay `true`
    update_mutation2 = """
    mutation {
      updateTermsAndConditions(
        marketingAccepted: true){
          id
        }
    }
    """

    conn |> post("/graphql", mutation_skeleton(update_mutation2))

    # Try to change the email now
    new_email = "test3@test.test"

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

  test "update marketing accepted policy", %{conn: conn} do
    update_mutation = """
    mutation {
      updateTermsAndConditions(
        marketingAccepted: true){
          marketingAccepted
        }
    }
    """

    result = conn |> post("/graphql", mutation_skeleton(update_mutation))

    assert json_response(result, 200)["data"]["updateTermsAndConditions"]["marketingAccepted"] ==
             true
  end

  test "update private policy accepted", %{conn: conn} do
    update_mutation = """
    mutation {
      updateTermsAndConditions(
        privacyPolicyAccepted: true){
          privacyPolicyAccepted
        }
    }
    """

    result = conn |> post("/graphql", mutation_skeleton(update_mutation))

    assert json_response(result, 200)["data"]["updateTermsAndConditions"]["privacyPolicyAccepted"] ==
             true
  end
end

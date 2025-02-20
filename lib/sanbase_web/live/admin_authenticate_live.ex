defmodule SanbaseWeb.AdminAuthenticateLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Accounts.User

  require Logger

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Santiment | Admin Login",
       valid_email: false,
       error: nil,
       email: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center py-6 px-4">
      <div class="items-center gap-6 w-full">
        <div class="border border-gray-300 rounded-lg p-6 max-w-md mx-auto">
          <form class="space-y-4" phx-change="validate_email" phx-submit="login">
            <div class="mb-8">
              <h3 class="text-gray-800 text-3xl font-bold">Sign in</h3>
              <p class="text-gray-500 text-sm mt-4 leading-relaxed">
                Sign in to your Santiment account and gain access to the Metric Registry
              </p>
            </div>

            <div>
              <label class="text-gray-800 text-sm mb-2 block">Email</label>
              <div class="relative flex items-center">
                <input
                  name="email"
                  type="email"
                  required
                  class="w-full text-sm text-gray-800 border border-gray-300 pl-4 pr-10 py-3 rounded-lg outline-blue-600"
                  placeholder="Enter email"
                  phx-debounce="200"
                  value={@email}
                />
              </div>

              <span :if={@error} class="text-red-600 text-sm">
                Email must be a valid @santiment.net email address
              </span>
            </div>

            <div class="!mt-8">
              <button
                type="submit"
                class={[
                  if(@valid_email, do: "bg-blue-600 hover:bg-blue-700", else: "bg-gray-400"),
                  "w-full shadow-xl py-2.5 px-4 text-sm tracking-wide rounded-lg text-white"
                ]}
                disabled={not @valid_email}
                phx-disable-with="Sending..."
              >
                Sign in
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("validate_email", %{"email" => ""}, socket) do
    {:noreply, socket |> assign(valid_email: false, error: nil)}
  end

  def handle_event("validate_email", %{"email" => email}, socket) do
    email = String.trim(email)

    case String.split(email, "@") do
      [first_part, "santiment.net"] when byte_size(first_part) > 2 ->
        {:noreply, socket |> assign(valid_email: true, error: nil)}

      _ ->
        {:noreply, socket |> assign(valid_email: false, error: true)}
    end
  end

  def handle_event("login", %{"email" => email}, socket) do
    case login(email) do
      {:ok, :login_email_sent} ->
        {:noreply,
         socket
         |> assign(valid_email: true, error: nil, email: nil)
         |> put_flash(:info, "Login email sent. Please check your inbox.")
         |> push_navigate(to: ~p"/admin2")}

      {:ok, :direct_login} ->
        {:noreply,
         socket
         |> assign(valid_email: true, error: nil, email: nil)
         |> push_navigate(to: ~p"/admin_auth/email_login?email=#{email}")}

      {:error, error} ->
        error_msg =
          """
          An error occurred while sending the login email. Please try again later.
          Error: #{inspect(error)}
          """

        Logger.error(error_msg)
        {:noreply, socket |> put_flash(:error, error_msg)}
    end
  end

  defp login(email) do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      "dev" -> direct_login(email)
      _ -> send_email_login(email)
    end
  end

  defp send_email_login(email) do
    with {:ok, %{first_login: first_login} = user} <- User.find_or_insert_by(:email, email, %{}),
         {:ok, user} <- User.Email.update_email_token(user),
         [_ | _] = host_parts <- get_origin_host_parts(),
         {:ok, _} <-
           User.Email.send_login_email(user, first_login, host_parts, %{is_admin_login: true}) do
      {:ok, :login_email_sent}
    end
  end

  defp direct_login(email) do
    case User.find_or_insert_by(:email, email, %{}) do
      {:ok, _user} -> {:ok, :direct_login}
      {:error, error} -> {:error, error}
    end
  end

  defp get_origin_host_parts() do
    admin_url = SanbaseWeb.Endpoint.admin_url()
    %URI{host: host} = URI.parse(admin_url)

    String.split(host, ".")
  end
end

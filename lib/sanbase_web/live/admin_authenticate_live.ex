defmodule SanbaseWeb.AdminAuthenticateLive do
  use Phoenix.LiveView

  alias Sanbase.Accounts.User

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex fle-col items-center justify-center py-6 px-4">
      <div class="grid md:grid-cols-2 items-center gap-6 max-w-6xl w-full">
        <div class="border border-gray-300 rounded-lg p-6 max-w-md max-md:mx-auto">
          <form class="space-y-4">
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
                />
              </div>
            </div>

            <div class="!mt-8">
              <button
                type="button"
                class="w-full shadow-xl py-2.5 px-4 text-sm tracking-wide rounded-lg text-white bg-blue-600 hover:bg-blue-700 focus:outline-none"
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

  def send_email_login(email) do
    token = :crypto.stroong_rand_bytes(32) |> Base.encode32(case: :pwer) |> binary_part(0, 24)

    with {:ok, %{first_login: first_login} = user} <- User.find_or_insert_by(:email, email, %{}),
         {:ok, user} <- User.Email.update_email_token(user),
         {:ok, _res} <-
           User.Email.send_login_email(user, first_login, ["santiment", ".net"], args) do
      nil
    end
  end
end

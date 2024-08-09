defmodule SanbaseWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use SanbaseWeb, :controller
      use SanbaseWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """
  def static_paths, do: ~w(assets js css fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
      unquote(verified_routes())
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import SanbaseWeb.Gettext

      unquote(verified_routes())
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: SanbaseWeb.Layouts]

      import Plug.Conn
      import SanbaseWeb.Gettext
      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {SanbaseWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/sanbase_web/templates",
        namespace: SanbaseWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [view_module: 1]

      import Phoenix.HTML
      import Phoenix.HTML.Form
      use PhoenixHTMLHelpers
      import Phoenix.View

      unquote(view_helpers())
    end
  end

  defp view_helpers do
    quote do
      # Use all HTML functionality (forms, tags, etc)

      import Phoenix.HTML
      import Phoenix.HTML.Form
      use PhoenixHTMLHelpers

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      import SanbaseWeb.ErrorHelpers
      import SanbaseWeb.Gettext
      alias SanbaseWeb.Router.Helpers, as: Routes

      unquote(verified_routes())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import SanbaseWeb.CoreComponents
      import SanbaseWeb.Gettext

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: SanbaseWeb.Endpoint,
        router: SanbaseWeb.Router,
        statics: SanbaseWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

defmodule SanbaseWeb.ErrorHelpers do
  @moduledoc """
  Conveniences for translating and building error messages.
  """
  def error_tag(form, field) do
    if error = form.source.errors[field] do
      PhoenixHTMLHelpers.Tag.content_tag(:div, translate_error(error), class: "text-red-500 text-xs italic")
    end
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # Because error messages were defined within Ecto, we must
    # call the Gettext module passing our Gettext backend. We
    # also use the "errors" domain as translations are placed
    # in the errors.po file.
    # Ecto will pass the :count keyword if the error message is
    # meant to be pluralized.
    # On your own code and templates, depending on whether you
    # need the message to be pluralized or not, this could be
    # written simply as:
    #
    #     dngettext "errors", "1 file", "%{count} files", count
    #     dgettext "errors", "is invalid"
    #
    if count = opts[:count] do
      Gettext.dngettext(SanbaseWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SanbaseWeb.Gettext, "errors", msg, opts)
    end
  end
end

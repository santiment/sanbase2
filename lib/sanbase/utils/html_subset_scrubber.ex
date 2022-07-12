defmodule Sanbase.Utils.HtmlSubsetScrubber do
  require HtmlSanitizeEx.Scrubber.Meta
  alias HtmlSanitizeEx.Scrubber.Meta

  Meta.remove_cdata_sections_before_scrub()
  Meta.strip_comments()

  @valid_schemes ["http", "https", "mailto"]

  Meta.allow_tag_with_uri_attributes("a", ["href"], @valid_schemes)
  Meta.allow_tag_with_these_attributes("a", ["name", "title", "class"])
  Meta.allow_tag_with_this_attribute_values("a", "target", ["_blank"])
  Meta.allow_tag_with_this_attribute_values("a", "rel", ["noopener", "noreferrer"])

  Meta.allow_tag_with_these_attributes("b", ["class", "id"])
  Meta.allow_tag_with_these_attributes("blockquote", ["class", "id"])
  Meta.allow_tag_with_these_attributes("br", ["class", "id"])
  Meta.allow_tag_with_these_attributes("code", ["class", "id"])
  Meta.allow_tag_with_these_attributes("del", ["class", "id"])
  Meta.allow_tag_with_these_attributes("em", ["class", "id"])
  Meta.allow_tag_with_these_attributes("h1", ["class", "id"])
  Meta.allow_tag_with_these_attributes("h2", ["class", "id"])
  Meta.allow_tag_with_these_attributes("h3", ["class", "id"])
  Meta.allow_tag_with_these_attributes("h4", ["class", "id"])
  Meta.allow_tag_with_these_attributes("h5", ["class", "id"])
  Meta.allow_tag_with_these_attributes("h6", ["class", "id"])
  Meta.allow_tag_with_these_attributes("hr", ["class", "id"])
  Meta.allow_tag_with_these_attributes("i", ["class", "id"])

  Meta.allow_tag_with_uri_attributes("img", ["src"], @valid_schemes)

  Meta.allow_tag_with_these_attributes("img", [
    "width",
    "height",
    "title",
    "alt",
    "class"
  ])

  Meta.allow_tag_with_these_attributes("li", ["class", "id"])
  Meta.allow_tag_with_these_attributes("ol", ["class", "id"])
  Meta.allow_tag_with_these_attributes("p", ["class", "id"])
  Meta.allow_tag_with_these_attributes("pre", ["class", "id"])
  Meta.allow_tag_with_these_attributes("span", ["class", "id"])
  Meta.allow_tag_with_these_attributes("strike", ["class", "id"])
  Meta.allow_tag_with_these_attributes("strong", ["class", "id"])
  Meta.allow_tag_with_these_attributes("table", ["class", "id"])
  Meta.allow_tag_with_these_attributes("tbody", ["class", "id"])
  Meta.allow_tag_with_these_attributes("td", ["class", "id"])
  Meta.allow_tag_with_these_attributes("th", ["class", "id"])
  Meta.allow_tag_with_these_attributes("thead", ["class", "id"])
  Meta.allow_tag_with_these_attributes("tr", ["class", "id"])
  Meta.allow_tag_with_these_attributes("u", ["class", "id"])
  Meta.allow_tag_with_these_attributes("ul", ["class", "id"])

  Meta.allow_tag_with_these_attributes("iframe", ["src"])
  Meta.allow_tag_with_these_attributes("figure", ["class", "id"])
  Meta.allow_tag_with_these_attributes("figcaption", ["class", "id"])

  Meta.strip_everything_not_covered()
end

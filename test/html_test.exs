defmodule Excessibility.HTMLTest do
  use ExUnit.Case, async: true

  alias Excessibility.HTML

  test "parses binary HTML content" do
    raw = "<div>Body</div>"

    result = HTML.wrap(raw)
    assert result =~ "Body"
    assert result =~ "<div>"
  end

  test "preserves existing structure if data-phx-main is true" do
    html =
      "<html data-phx-main=\"true\"><head><title>Title</title></head><body>Main</body></html>"

    raw = html

    result = HTML.wrap(raw)

    assert String.contains?(result, "data-phx-main")
    assert result =~ ~r/<body>.*Main.*<\/body>/s
  end

  test "prefixes static paths for href/src" do
    content = "<img src=\"/images/foo.png\"><link href=\"/styles.css\">"
    result = HTML.wrap(content)

    assert result =~ "file://"
    assert result =~ "/images/foo.png"
    assert result =~ "/styles.css"
  end

  test "extracts and preserves lang attribute from endpoint when wrapping LiveView div" do
    # Simulate a LiveView div with phx-main attribute
    liveview_content = {"div", [{"data-phx-main", "true"}], ["LiveView Content"]}

    result = HTML.wrap(liveview_content)

    # Should have lang="en" from the test endpoint
    assert result =~ ~r/<html[^>]*lang="en"/
    # Should preserve the content
    assert result =~ "LiveView Content"
  end

  test "extracts and preserves multiple HTML attributes when wrapping content" do
    # Simulate a generic fragment that needs wrapping
    fragment = {"div", [], ["Fragment Content"]}

    result = HTML.wrap(fragment)

    # Should have both lang and dir attributes from test endpoint
    assert result =~ ~r/<html[^>]*lang="en"/
    assert result =~ ~r/<html[^>]*dir="ltr"/
    # Should have the head content from endpoint
    assert result =~ "Test App"
    assert result =~ "Fragment Content"
  end

  test "preserves existing lang attribute when HTML is already complete" do
    complete_html =
      {"html", [{"lang", "fr"}, {"dir", "rtl"}],
       [
         {"head", [], [{"title", [], ["French Title"]}]},
         {"body", [], ["French Content"]}
       ]}

    result = HTML.wrap(complete_html)

    # Should preserve the original lang="fr", not replace with endpoint's lang="en"
    assert result =~ ~r/<html[^>]*lang="fr"/
    assert result =~ ~r/<html[^>]*dir="rtl"/
    assert result =~ "French Title"
    assert result =~ "French Content"
  end

  test "handles missing lang attribute gracefully" do
    # Even if endpoint returns no lang, should not crash
    fragment = {"p", [], ["Simple paragraph"]}

    result = HTML.wrap(fragment)

    # Should complete successfully and contain the content
    assert result =~ "Simple paragraph"
    assert result =~ "<html"
  end
end

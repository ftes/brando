defmodule E2eProject.E2e.Forms.FormSubmissionsTest do
  use E2eProject.PlaywrightCase

  # A published contact form in a page block (E2EFixtureController `site-form`).
  # The page serves stored block HTML, so these also cover the CSRF token being
  # filled in per request.
  setup %{page: page} do
    response = Playwright.APIRequestContext.post!(Page.request(page), "/e2e/setup_fixtures/site-form")
    assert Playwright.APIResponse.ok(response)
    :ok
  end

  test "a visitor sends the form and an editor reads it", %{page: page} do
    Page.goto!(page, "/contact-us")
    form = Page.locator(page, "form#form-contact")
    csrf = Locator.locator(form, ~s|input[name="_csrf_token"]|)
    Expect.not_to_have_value!(csrf, "$csrftoken")
    # As a cache in front of the site would serve it: someone else's token, which the script replaces
    Locator.evaluate!(csrf, "input => { input.value = 'cached-for-someone-else' }")

    # Sent empty: the required fields are marked where they are
    Locator.locator(form, ~s|input[name="fields[name]"]|) |> Locator.evaluate!("input => input.removeAttribute('required')")
    Locator.locator(form, ~s|input[name="fields[email]"]|) |> Locator.evaluate!("input => input.removeAttribute('required')")
    form |> Locator.get_by_role(:button, name: "Send") |> Locator.click!()

    Expect.to_have_attribute!(
      Locator.locator(form, ~s|input[name="fields[email]"]|),
      "aria-invalid",
      "true"
    )

    Expect.to_be_visible!(Locator.locator(form, ~s|.site-form-field[data-key="name"] .site-form-error|))

    form |> Locator.get_by_label("Name") |> Locator.fill!("Ada Lovelace")
    form |> Locator.get_by_label("Email") |> Locator.fill!("ada@example.com")
    form |> Locator.get_by_label("Message") |> Locator.fill!("About the engine")
    form |> Locator.get_by_role(:button, name: "Send") |> Locator.click!()

    Expect.to_be_visible!(Page.locator(page, "#form-contact-sent"))
    Expect.to_be_hidden!(Locator.locator(form, ".site-form-actions"))

    Page.goto!(page, "/admin/forms")
    sync_lv(page)
    page |> Page.locator("#form-inbox-contact") |> Locator.get_by_role(:link, name: "Open") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/forms/contact/submissions"))
    sync_lv(page)
    row = Page.locator(page, ".form-submissions-table tbody tr") |> Locator.first()
    Expect.to_contain_text!(row, "Ada Lovelace")
    row |> Locator.get_by_role(:button, name: "Open") |> Locator.click!()
    Expect.to_contain_text!(Page.locator(page, "#submission-detail"), "About the engine")
  end

  test "without JavaScript a post lands back on the page at its message", %{
    browser: browser,
    sandbox_user_agent: user_agent
  } do
    # Same sandbox user agent, so the post reaches this test's data
    context =
      Browser.new_context!(browser,
        base_url: base_url(),
        user_agent: user_agent,
        java_script_enabled: false
      )

    visitor = BrowserContext.new_page!(context)

    Page.goto!(visitor, "/contact-us")
    Page.get_by_label(visitor, "Name") |> Locator.fill!("Grace Hopper")
    Page.get_by_label(visitor, "Email") |> Locator.fill!("grace@example.com")
    Page.get_by_role(visitor, :button, name: "Send") |> Locator.click!()

    Expect.to_have_url!(visitor, ~r"/contact-us#form-contact-sent$")
    Expect.to_be_visible!(Page.locator(visitor, "#form-contact-sent"))
    Expect.to_be_hidden!(Page.locator(visitor, "#form-contact-failed"))
    BrowserContext.close!(context)
  end

  # The site's wording for form messages: messages_live_test.exs edits it,
  # and submission_controller_test.exs checks the reply the page shows.
end

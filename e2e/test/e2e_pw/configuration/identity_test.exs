defmodule E2eProject.E2e.Configuration.IdentityTest do
  use E2eProject.PlaywrightCase

  defp add_entry(page) do
    page
    |> Page.locator("#identity_links-field-base")
    |> Locator.get_by_role(:button, name: "Add entry")
    |> Locator.click!()
  end

  defp fill_label(page, label, value),
    do: Page.get_by_label(page, label, exact: true) |> Locator.fill!(value)

  test "update identity", %{page: page} do
    # Go to the /admin page
    Page.goto!(page, "/admin")

    # Wait for navigation and check that the URL is /admin
    Expect.to_have_url!(page, e2e_url("/admin"))
    # The sticky nav joins after the page: a click on its server render is lost
    sync_lv(page)

    Page.get_by_text(page, "Configuration") |> Locator.click!()
    Page.get_by_text(page, "Identity") |> Locator.click!()

    Expect.to_have_url!(page, e2e_url("/admin/config/identity"))

    fill_label(page, "Name", "Acme Organization")
    fill_label(page, "Alternate name", "Acme Org")
    fill_label(page, "Email", "info@acme.com")
    fill_label(page, "Phone", "+47 987 65 432")
    fill_label(page, "Address line 1", "Acme Street 1")
    fill_label(page, "Address line 2", "Walkup 1")
    fill_label(page, "City", "Oslo")
    fill_label(page, "Zip code", "0101")
    fill_label(page, "Title (prefix)", "Acme // ")
    fill_label(page, "Title", "Hello!")

    add_entry(page)
    Page.locator(page, "#identity_links_0_name") |> Locator.fill!("Instagram")
    Page.locator(page, "#identity_links_0_url") |> Locator.fill!("https://instagram.com/acme")

    add_entry(page)
    Page.locator(page, "#identity_links_1_name") |> Locator.fill!("Facebook")
    Page.locator(page, "#identity_links_1_url") |> Locator.fill!("https://facebook.com/acme")

    add_entry(page)
    Page.locator(page, "#identity_links_2_name") |> Locator.fill!("Twitter")
    Page.locator(page, "#identity_links_2_url") |> Locator.fill!("https://twitter.com/acme")

    sync_lv(page)

    page
    |> Page.locator(~S|button[name="identity\[drop_links_ids\]\[\]"]|)
    |> Locator.nth(1)
    |> Locator.click!()

    # The save has landed when the form's save state goes from dirty to clean
    save_state = Page.locator(page, ".draft-save-state") |> Locator.first()
    Expect.to_have_attribute!(save_state, "data-state", "dirty")
    Page.get_by_test_id(page, "submit") |> Locator.click!()
    Expect.to_have_attribute!(save_state, "data-state", "clean", timeout: 15_000)

    Page.goto!(page, "/")
    Expect.to_have_title!(page, "Acme // Index")

    Expect.to_have_count!(
      Page.locator(page, ~s|meta[property="og:see_also"][content="https://twitter.com/acme"]|),
      1
    )

    Expect.to_have_count!(
      Page.locator(page, ~s|meta[property="og:see_also"][content="https://instagram.com/acme"]|),
      1
    )
  end
end

defmodule E2eProject.E2e.Assets.GalleriesTest do
  use E2eProject.PlaywrightCase

  test "lists galleries and edits a gallery", %{page: page} do
    Page.goto!(page, "/admin")
    Expect.to_have_class!(Page.locator(page, "#brando-nav"), ~r/phx-connected/)

    # Navigate to galleries via menu (expand Assets submenu first)
    Page.get_by_text(page, "Assets", exact: true) |> Locator.click!()
    Page.get_by_role(page, :link, name: "Galleries") |> Locator.click!()
    sync_lv(page)

    # Verify we're on the galleries listing page
    Expect.to_have_url!(page, ~r"/admin/assets/galleries")

    # Verify gallery rows are visible (seeded 2 galleries)
    rows = Page.locator(page, ".content-list .list-row")
    Expect.to_have_count!(rows, 2)

    # Verify config_target is shown
    Expect.to_contain_text!(Locator.first(rows), "Gallery")

    # Click edit on the first gallery via the dropdown menu
    rows |> Locator.first() |> Locator.locator(".circle-dropdown") |> Locator.click!()
    Page.get_by_role(page, :button, name: ~r/Edit/) |> Locator.click!()
    sync_lv(page)

    # Verify we're on the edit page
    Expect.to_have_url!(page, ~r"/admin/assets/galleries/update/")

    # Edit the config_target field
    config_target_input = Page.get_by_role(page, :textbox, name: "Configuration target")
    Expect.to_be_visible!(config_target_input)
    Locator.click!(config_target_input)
    Locator.fill!(config_target_input, "updated_target")

    # Save the form
    Page.get_by_test_id(page, "submit") |> Locator.click!()

    # Verify we're back on the listing page
    Expect.to_have_url!(page, ~r"/admin/assets/galleries")
    sync_lv(page)

    # Reopen to verify the configuration persisted.
    rows |> Locator.first() |> Locator.get_by_role(:link, name: ~r/Gallery/) |> Locator.click!()

    Expect.to_have_value!(
      Page.get_by_role(page, :textbox, name: "Configuration target"),
      "updated_target"
    )
  end
end

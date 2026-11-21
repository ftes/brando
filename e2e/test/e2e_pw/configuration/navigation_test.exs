defmodule E2eProject.E2e.Configuration.NavigationTest do
  use E2eProject.PlaywrightCase

  alias Playwright.Mouse

  # Deactivating, creating and removing menu items are LiveView tests in
  # test/brando_admin/live/navigation_live_test.exs. Reordering needs a drag.

  test "reorder menu items", %{page: page} do
    Page.goto!(page, "/admin")
    Page.get_by_text(page, "Configuration") |> Locator.click!()

    page
    |> Page.locator("#nav-sections")
    |> Locator.get_by_role(:link, name: "Navigation")
    |> Locator.click!()

    Expect.to_have_url!(page, e2e_url("/admin/config/navigation/menus"))
    Page.get_by_role(page, :link, name: "Main menu") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/config/navigation/menus/update/1"))

    Page.locator(page, ".subform-handle") |> Locator.first() |> Locator.hover!()
    Mouse.down!(Page.mouse(page))
    # The third row's handle. Rows hold their own hidden inputs, so a row is
    # addressed as a row rather than by its place among the container's nodes.
    third =
      page
      |> Page.locator(".subform-entry")
      |> Locator.nth(2)
      |> Locator.locator(".subform-tools > .subform-handle")

    Locator.hover!(third)
    Locator.hover!(third)
    Page.wait_for_timeout(page, 300)
    Mouse.up!(Page.mouse(page))

    sync_lv(page)
    Page.get_by_test_id(page, "submit") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/config/navigation/menus"))
    sync_lv(page)

    Page.goto!(page, "/")

    # Wait for the menu items to be loaded
    Page.wait_for_selector!(page, "[data-menu-item-key]")

    # Get all elements with data-menu-item-key in DOM order
    menu_item_keys =
      Page.eval_on_selector_all!(
        page,
        "[data-menu-item-key]",
        "elements => elements.map(el => el.getAttribute('data-menu-item-key'))"
      )

    # Check that both keys are present
    assert "brando" in menu_item_keys
    assert "guides" in menu_item_keys

    # Assert that 'brando' comes after 'guides'
    brando_index = Enum.find_index(menu_item_keys, &(&1 == "brando"))
    guides_index = Enum.find_index(menu_item_keys, &(&1 == "guides"))
    assert brando_index > guides_index
  end
end

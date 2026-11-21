defmodule E2eProject.E2e.Configuration.CacheTest do
  use E2eProject.PlaywrightCase

  test "has cache and clears cache", %{page: page} do
    Page.set_viewport_size!(page, %{width: 1440, height: 1000})
    # create a cached page
    Page.goto!(page, "/")
    Expect.to_be_visible!(Page.get_by_role(page, :link, name: "Brando CMS"))

    Page.goto!(page, "/admin")
    sync_lv(page)
    Page.get_by_text(page, "Configuration") |> Locator.click!()
    Page.get_by_role(page, :link, name: "Cache") |> Locator.click!()
    Expect.to_have_url!(page, e2e_url("/admin/config/cache"))

    sync_lv(page)
    # Query caches survive individual SQL sandboxes, so other pages may already
    # be cached. Clear the homepage's single-entry cache, not every pages row.
    cached_page =
      page
      |> Page.get_by_role(:row)
      |> Locator.filter(has: Page.get_by_role(page, :cell, name: "pages", exact: true))
      |> Locator.filter(has: Page.get_by_role(page, :cell, name: "#1", exact: true))

    Expect.to_be_visible!(cached_page)

    Page.screenshot!(page, path: Playwright.Test.output_path("cache-desktop.png"), full_page: true)
    cached_page |> Locator.get_by_role(:button, name: ~r/^Clear cache/) |> Locator.click!()
    Expect.to_have_count!(cached_page, 0)
    Expect.to_be_visible!(Page.get_by_role(page, :cell, name: "users", exact: true) |> Locator.first())
    Page.get_by_role(page, :button, name: "Empty all caches") |> Locator.click!()
    Expect.to_have_count!(Page.get_by_role(page, :cell, name: "pages", exact: true), 0)
    Expect.to_be_visible!(Page.get_by_role(page, :heading, name: "No cached entries"))
    Page.screenshot!(page, path: Playwright.Test.output_path("cache-empty-desktop.png"), full_page: true)
  end
end

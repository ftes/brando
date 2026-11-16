defmodule E2eProject.E2e.Assets.AltTextTest do
  use E2eProject.PlaywrightCase

  # Structural locators only: labels are translated and must not be pinned.
  test "the image library links to the alt text page, which lists the gap", %{page: page} do
    Page.goto!(page, "/admin/assets/images")
    sync_lv(page)

    link = Page.get_by_test_id(page, "alt-text-link")
    Expect.to_be_visible!(link)
    Locator.click!(link)
    Expect.to_have_url!(page, e2e_url("/admin/assets/images/alt-text"))
    sync_lv(page)

    panel = Page.locator(page, ".alt-text-panel")
    Expect.to_be_visible!(Locator.locator(panel, ".workspace-panel-heading h2"))
    Expect.to_have_text!(Locator.locator(panel, ".workspace-panel-heading > span"), ~r/^\d+$/)

    # Without an AI provider nothing can be sent; with one, the estimate
    # stands before the button that sends.
    describe = Locator.locator(panel, ~s|button[phx-click="describe"]|)

    if Locator.count!(describe) > 0 do
      Expect.to_be_visible!(Locator.locator(panel, ".alt-text-estimate p") |> Locator.first())
    end

    Page.set_viewport_size!(page, %{width: 390, height: 844})

    Expect.poll!(fn -> Page.evaluate!(page, "document.documentElement.scrollWidth") end, &assert(&1 <= 390))
  end
end

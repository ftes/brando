defmodule E2eProject.E2e.PreviewControlsTest do
  use E2eProject.PlaywrightCase

  alias Playwright.{Keyboard, Mouse}

  test "preview resize keeps capture across the iframe and bounds, and devices retain selection", %{page: page} do
    request = Page.request(page)
    Playwright.APIRequestContext.post!(request, "/e2e/setup_fixtures/norwegian-admin-user")
    Page.set_viewport_size!(page, %{width: 1600, height: 1000})
    Page.goto!(page, "/admin/pages/update/1")
    sync_lv(page)
    Page.locator(page, ".live-preview-toggle") |> Locator.click!()
    Page.locator(page, ".preview-choice") |> Locator.first() |> Locator.click!()
    wait_for_preview_ready(page)
    preview = Page.locator(page, ".live-preview")
    divider = Page.get_by_role(page, :separator, name: "Endre størrelse på forhåndsvisning")

    width = fn ->
      Locator.evaluate!(preview, "el => Math.round(el.getBoundingClientRect().width)")
    end

    Expect.poll!(width, &assert(&1 == 600))
    handle = Locator.bounding_box!(divider)
    assert handle.height > 900
    mouse = Page.mouse(page)
    Mouse.move!(mouse, handle.x + 5, handle.y + 220)
    Mouse.down!(mouse)
    # Go well past the smallest width, then back, without releasing. The old
    # resizer terminated the drag at the boundary (and when entering iframe).
    Mouse.move!(mouse, 1580, 450, steps: 5)
    Expect.poll!(width, &assert(&1 == 320))
    Mouse.move!(mouse, handle.x - 60, 450, steps: 5)
    Expect.poll!(width, &assert(&1 == 665))
    Mouse.move!(mouse, 100, 450, steps: 5)
    Expect.poll!(width, &assert(&1 == 795))
    Mouse.move!(mouse, handle.x + 5, 450, steps: 5)
    Expect.poll!(width, &assert(&1 == 600))
    Mouse.up!(mouse)
    Expect.not_to_have_class!(preview, ~r/is-resizing/)

    Locator.focus!(divider)
    keyboard = Page.keyboard(page)
    Keyboard.press!(keyboard, "ArrowRight")
    Expect.poll!(width, &assert(&1 == 576))
    Keyboard.press!(keyboard, "ArrowLeft")
    Expect.poll!(width, &assert(&1 == 600))
    mobile = Page.get_by_role(page, :button, name: "375px", exact: true)
    Locator.click!(mobile)
    Expect.to_have_attribute!(mobile, "aria-pressed", "true")

    Expect.to_have_attribute!(
      Page.locator(page, "#live-preview-frame"),
      "data-live-preview-device",
      "mobile"
    )

    Expect.poll!(width, &assert(&1 == 375))
    Page.set_viewport_size!(page, %{width: 1440, height: 1000})
    Expect.to_have_attribute!(mobile, "aria-pressed", "true")
    Expect.poll!(width, &assert(&1 == 375))
    Page.get_by_role(page, :button, name: "768px", exact: true) |> Locator.hover!()
    Page.screenshot!(page, path: Playwright.Test.output_path("preview-toolbar.png"))
    Page.get_by_role(page, :button, name: "Oppdater", exact: true) |> Locator.click!()
    wait_for_preview_ready(page)
    Expect.to_have_attribute!(mobile, "aria-pressed", "true")
    # Closing from the keyboard returns focus to the trigger, not to the page.
    Page.get_by_role(page, :button, name: "Lukk forhåndsvisningen", exact: true) |> Locator.focus!()
    Keyboard.press!(keyboard, "Enter")
    Expect.to_have_count!(preview, 0)
    trigger = Page.locator(page, ".preview-chooser-trigger")
    Expect.not_to_have_class!(trigger, ~r/active/)
    Expect.to_be_focused!(trigger)
  end
end

defmodule E2eProject.E2e.Blocks.BlockCollapseTest do
  use E2eProject.PlaywrightCase

  alias E2eProject.Latency

  @held_ms 1500

  # Collapsing a block is a checkbox in its form. The block and the eye icon
  # change at once rather than when the validate reply comes back, which is
  # instant on a local server and a visible lag on a real connection. Server
  # frames are held back here, so the first half of each step passes only if
  # the page changes on its own.
  describe "Collapsing a block" do
    @describetag timeout: 90_000

    test "shows at once, before the server replies, and is saved", %{page: page} do
      latency = Latency.install(page)

      Page.goto!(page, "/admin/pages/create")
      sync_lv(page)
      Page.get_by_label(page, "Title", exact: true) |> Locator.fill!("Collapse Test")
      Page.get_by_label(page, "URI") |> Locator.fill!("collapse-test")

      Page.get_by_role(page, :button, name: "Add block") |> Locator.last() |> Locator.click!()
      Page.get_by_role(page, :button, name: "05 LIVE PREVIEW TEST") |> Locator.click!()

      Expect.to_contain_text!(
        Page.locator(page, ".module-picker-namespace.active"),
        "05 LIVE PREVIEW TEST"
      )

      Page.get_by_role(page, :button, name: "Styled Header") |> Locator.click!()
      sync_lv(page)

      block = Page.locator(page, ".base-block") |> Locator.first()
      toggler = block |> Locator.locator(".block-actions label.toggler") |> Locator.first()
      content = Locator.locator(block, ".header-block textarea")
      Expect.to_be_visible!(content)
      Expect.to_be_visible!(Locator.locator(toggler, ".when-expanded"))
      Expect.to_be_hidden!(Locator.locator(toggler, ".when-collapsed"))

      Latency.set(latency, @held_ms)
      Locator.click!(toggler)
      Expect.to_have_class!(block, ~r/\bcollapsed\b/, timeout: 500)
      Expect.to_be_hidden!(content, timeout: 500)
      Expect.to_be_visible!(Locator.locator(toggler, ".when-collapsed"), timeout: 500)
      Expect.to_be_hidden!(Locator.locator(toggler, ".when-expanded"))

      # The held reply lands and agrees.
      Latency.set(latency, 0)
      sync_lv(page)
      Expect.to_have_class!(block, ~r/\bcollapsed\b/)

      Latency.set(latency, @held_ms)
      Locator.click!(toggler)
      Expect.not_to_have_class!(block, ~r/\bcollapsed\b/, timeout: 500)
      Expect.to_be_visible!(content, timeout: 500)
      Expect.to_be_visible!(Locator.locator(toggler, ".when-expanded"), timeout: 500)

      Latency.set(latency, 0)
      sync_lv(page)
      Expect.not_to_have_class!(block, ~r/\bcollapsed\b/)

      # Collapse again and check the server kept it.
      Locator.click!(toggler)
      sync_lv(page)
      Page.get_by_test_id(page, "split-dropdown-button") |> Locator.click!()
      Page.get_by_role(page, :button, name: ~r/Save and continue editing/) |> Locator.click!()
      Expect.to_have_url!(page, ~r"/update/", timeout: 30_000)
      sync_lv(page)

      Page.reload!(page)
      sync_lv(page)
      Expect.to_have_class!(block, ~r/\bcollapsed\b/)
      Expect.to_be_visible!(Locator.locator(toggler, ".when-collapsed"))
    end
  end
end

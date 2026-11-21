defmodule E2eProject.E2e.Blocks.BlockSaveContinueTest do
  use E2eProject.PlaywrightCase

  # Regression guard for the post-save re-seed (the `replace_form` cascade).
  #
  # Blocks own their forms exclusively: after a save-and-continue, every
  # mounted block component must be re-seeded with the freshly persisted data
  # (new db ids). Without the re-seed, the next save diffs against stale
  # nil-id state: nested rows (vars/refs/children) lose their identity and
  # get duplicated or churned, and edits made after the first save can be
  # lost. Other specs always save-then-navigate, which never exercises this.
  describe "Save and continue editing" do
    @describetag timeout: 90_000

    defp save_and_continue(page) do
      Page.get_by_test_id(page, "split-dropdown-button") |> Locator.click!()
      Page.get_by_role(page, :button, name: ~r/Save and continue editing/) |> Locator.click!()
      Expect.to_have_url!(page, ~r"/update/", timeout: 30_000)
      sync_lv(page)
      Expect.not_to_be_visible!(Page.locator(page, ".alert.error"), timeout: 5000)
      # let the post-save replace_form re-seed land before further edits
      Page.wait_for_timeout(page, 750)
    end

    test "block edits survive repeated save-and-continue without duplication", %{page: page} do
      Page.goto!(page, "/admin/pages/create")
      sync_lv(page)
      Page.get_by_label(page, "Title", exact: true) |> Locator.fill!("Save Continue Test")
      Page.get_by_label(page, "URI") |> Locator.fill!("save-continue-test")

      Page.get_by_role(page, :button, name: "Add block") |> Locator.last() |> Locator.click!()
      Page.get_by_role(page, :button, name: "05 LIVE PREVIEW TEST") |> Locator.click!()

      Expect.to_contain_text!(
        Page.locator(page, ".module-picker-namespace.active"),
        "05 LIVE PREVIEW TEST"
      )

      Page.get_by_role(page, :button, name: "Styled Header") |> Locator.click!()
      sync_lv(page)

      header_text = Page.locator(page, ".header-block textarea")
      Locator.fill!(header_text, "First")
      Locator.blur!(header_text)
      sync_lv(page)

      save_and_continue(page)

      # exactly one block with one header ref after the first save
      Expect.to_have_count!(Page.locator(page, ".entry-block"), 1)
      Expect.to_have_count!(Page.locator(page, ".header-block textarea"), 1)
      Expect.to_have_value!(Page.locator(page, ".header-block textarea"), "First")

      # edit in the SAME session: the component must now hold persisted ids
      Page.locator(page, ".header-block textarea") |> Locator.fill!("Edited after save")
      Page.locator(page, ".header-block textarea") |> Locator.blur!()
      sync_lv(page)

      save_and_continue(page)

      Expect.to_have_count!(Page.locator(page, ".entry-block"), 1)
      Expect.to_have_count!(Page.locator(page, ".header-block textarea"), 1)
      Expect.to_have_value!(Page.locator(page, ".header-block textarea"), "Edited after save")

      # full reopen: the persisted state is the truth
      Page.goto!(page, "/admin/pages")
      sync_lv(page)
      Page.get_by_role(page, :link, name: "Save Continue Test", exact: true) |> Locator.click!()
      sync_lv(page)

      Expect.to_have_count!(Page.locator(page, ".entry-block"), 1)
      Expect.to_have_count!(Page.locator(page, ".header-block textarea"), 1)
      Expect.to_have_value!(Page.locator(page, ".header-block textarea"), "Edited after save")
    end
  end
end

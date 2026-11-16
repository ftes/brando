defmodule E2eProject.E2e.ChangeTrackingTest do
  use E2eProject.PlaywrightCase

  defp form_values(page),
    do: Page.locator(page, "#tracking-form") |> Locator.evaluate!("form => Object.fromEntries(new FormData(form))")

  defp editor(page), do: Page.locator(page, "#tracking_code-code .cm-content")

  setup %{page: page} do
    Page.goto!(page, "/admin/__change_tracking")
    Expect.to_have_text!(editor(page), "original source")
    Expect.to_have_value!(Page.locator(page, "#tracking_date"), "2026-09-01")
    :ok
  end

  test "parent replacement and clearing reach ignored widgets without echoing edits", %{page: page} do
    Page.locator(page, "#replace-values") |> Locator.click!()
    Expect.to_have_text!(editor(page), "restored source")
    Expect.to_have_value!(Page.locator(page, "#tracking_date"), "2026-09-08")
    Expect.to_have_value!(Page.locator(page, "#tracking_datetime"), "2026-09-08T15:30:00.000Z")

    Expect.to_have_value!(
      Page.locator(page, ~s|#tracking_date-datepicker input:not([type="hidden"])|),
      "08/09/26"
    )

    Expect.to_have_text!(Page.locator(page, "#change-count"), "0")
    Expect.to_have_count!(Page.locator(page, ~s|[name="tracking[date]"]|), 1)
    Expect.to_have_count!(Page.locator(page, ~s|[name="tracking[datetime]"]|), 1)
    Page.locator(page, "#submit-values") |> Locator.click!()
    Expect.to_contain_text!(Page.locator(page, "#submitted-values"), "restored source")

    Locator.click!(editor(page))
    Locator.press!(editor(page), "ControlOrMeta+a")
    Playwright.Keyboard.insert_text!(Page.keyboard(page), "edited after restore")
    Expect.to_have_text!(Page.locator(page, "#change-count"), "1")
    Page.locator(page, "#unrelated-update") |> Locator.click!()
    Expect.to_have_text!(Page.locator(page, "#tick-count"), "1")
    Expect.to_have_text!(editor(page), "edited after restore")
    assert form_values(page)["tracking[code]"] == "edited after restore"

    Page.locator(page, "#clear-values") |> Locator.click!()
    Expect.to_have_text!(editor(page), "")
    Expect.to_have_value!(Page.locator(page, "#tracking_date"), "")
    Expect.to_have_value!(Page.locator(page, "#tracking_datetime"), "")
    Expect.to_have_value!(Page.locator(page, ~s|#tracking_date-datepicker input:not([type="hidden"])|), "")
    Expect.to_have_text!(Page.locator(page, "#change-count"), "1")
    Page.locator(page, "#submit-values") |> Locator.click!()

    Expect.to_have_text!(
      Page.locator(page, "#submitted-values"),
      ~s({"code":"","date":"","datetime":""})
    )
  end

  test "unrelated patches preserve local edits and removing controls destroys their widgets", %{page: page} do
    # No input event: this represents an edit waiting for its debounce/commit.
    Page.evaluate!(page, """
    () => {
      const date = document.querySelector('#tracking_date')
      date._flatpickr.setDate('2026-09-05', false)
      const hook = window.liveSocket.main.getHook(document.querySelector('#tracking_code-code'))
      window.trackingEditor = hook.view
      hook.view.update([hook.view.state.update({ changes: { from: 0, to: hook.view.state.doc.length, insert: 'pending source' } })])
      hook.$input.value = 'pending source'
    }
    """)

    Page.locator(page, "#unrelated-update") |> Locator.click!()
    Expect.to_have_text!(Page.locator(page, "#tick-count"), "1")
    Expect.to_have_text!(editor(page), "pending source")
    assert form_values(page)["tracking[code]"] == "pending source"
    Expect.to_have_value!(Page.locator(page, "#tracking_date"), "2026-09-05")
    Expect.to_have_text!(Page.locator(page, "#change-count"), "0")
    Page.locator(page, "#remove-controls") |> Locator.click!()
    Expect.to_have_count!(editor(page), 0)
    Expect.to_have_count!(Page.locator(page, ".flatpickr-calendar"), 0)
    assert Page.evaluate!(page, "() => window.trackingEditor.destroyed") == true
  end
end

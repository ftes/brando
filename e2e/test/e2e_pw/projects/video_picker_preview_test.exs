defmodule E2eProject.E2e.Projects.VideoPickerPreviewTest do
  use E2eProject.PlaywrightCase

  # The video picker's preview plays what the server builds from the stored row.
  # A stored address is never an iframe's src. The changeset refuses a script-scheme
  # address, so a row stored before that is covered in video_picker_preview_test.exs.

  @youtube_embed "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1"
  @config_target "video:E2eProject.Projects.Project:cover_video"

  defp open_preview(page, slug, video) do
    # No request leaves the test; the iframe's src is what counts
    Page.route!(page, ~r/youtube\.com|vimeo\.com|example\.com/, &Playwright.Route.abort!/1)

    factory(
      page,
      "Brando.Videos.Video",
      Map.merge(%{status: "ready", config_target: @config_target, title: slug}, video)
    )

    client =
      factory(page, "E2eProject.Projects.Client", %{
        name: slug,
        slug: slug,
        status: "published",
        language: "en"
      })

    project =
      factory(page, "E2eProject.Projects.Project", %{
        title: slug,
        slug: slug,
        client_id: client["id"],
        status: "published",
        language: "en",
        introduction: "<p>Intro</p>"
      })

    Page.goto!(page, "/admin/projects/projects/update/#{project["id"]}")
    sync_lv(page)

    picker = Page.locator(page, "#video-picker")

    page
    |> Page.locator("#project_cover_video-media")
    |> Locator.get_by_role(:button, name: "Select video", exact: true)
    |> Locator.click!()

    Expect.to_be_visible!(picker)

    picker
    |> Locator.locator(".video-picker__video")
    |> Locator.filter(has_text: slug)
    |> Locator.locator(".video-preview")
    |> Locator.click!()

    modal = Page.locator(page, "#video-player-modal")
    Expect.to_have_count!(Locator.locator(modal, ".video-not-loaded"), 0)
    modal
  end

  embeds = [
    {"youtube-id",
     %{type: "youtube", source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", remote_id: "dQw4w9WgXcQ"},
     @youtube_embed},
    {"youtube-address-only", %{type: "youtube", source_url: "https://youtu.be/dQw4w9WgXcQ"}, @youtube_embed},
    {"vimeo-address-only", %{type: "vimeo", source_url: "https://vimeo.com/76979871/abcdef1234"},
     "https://player.vimeo.com/video/76979871?h=abcdef1234&autoplay=1"}
  ]

  for {slug, video, src} <- embeds do
    test "previews #{slug} in the provider's player", %{page: page} do
      modal = open_preview(page, "preview-#{unquote(slug)}", unquote(Macro.escape(video)))
      Expect.to_have_attribute!(Locator.locator(modal, "iframe"), "src", unquote(src))
    end
  end

  test "previews a linked file in a video element", %{page: page} do
    modal =
      open_preview(page, "preview-file", %{
        type: "external_file",
        source_url: "https://example.com/clip.mp4"
      })

    Expect.to_have_attribute!(
      Locator.locator(modal, "video source"),
      "src",
      "https://example.com/clip.mp4"
    )

    Expect.to_have_count!(Locator.locator(modal, "iframe"), 0)
  end

  test "an address that is not the provider's plays nothing", %{page: page} do
    modal =
      open_preview(page, "preview-elsewhere", %{
        type: "youtube",
        source_url: "https://example.com/elsewhere"
      })

    Expect.to_be_visible!(Locator.locator(modal, ".video-not-supported"))
    Expect.to_have_count!(Locator.locator(modal, "iframe"), 0)
  end
end

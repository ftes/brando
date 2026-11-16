Logger.configure(level: :warning)
Application.ensure_all_started(:inets)
ExUnit.start(exclude: [:skip], timeout: 60_000)

{:ok, _apps} = Application.ensure_all_started(:credo)

ExUnit.start(capture_log: true, timeout: 1_000)

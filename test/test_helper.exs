# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

{:ok, _apps} = Application.ensure_all_started(:credo)

ExUnit.start(capture_log: true, timeout: 1_000)

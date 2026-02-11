Code.require_file("support/fixtures.ex", __DIR__)

Mimic.copy(WebSockex)
Mimic.copy(ExCoinbase.WebSocket.Client)
Mimic.copy(ExCoinbase.WebSocket)
Mimic.copy(ExCoinbase.JWT)

ExUnit.start()

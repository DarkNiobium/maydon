# MAYDON online server

One headless Godot process does matchmaking (rooms with codes, "find teammates", queue per mode,
bots fill empty slots after 10/12/15 s for 3v3/5v5/11v11) and starts one dedicated headless match
process per game (host-authoritative, the same simulation as the phone).

* Matchmaker: WebSocket, **TCP 47900** — clients connect to `ws://HOST:47900`
* Matches: ENet, **UDP 47910–47990** (one port per running match)
* CPU: ~1–2 ms per simulated tick for 11v11 → a small VPS (1 vCPU) runs several matches.

## Run
* Docker (from the repo root): `docker build -f server/Dockerfile -t maydon-server . && docker run -d --restart unless-stopped -p 47900:47900/tcp -p 47910-47990:47910-47990/udp maydon-server`
* Without Docker: install Godot 4.7, then `server/run_local.sh`

## Point the game at it
* For testing: in the game **Settings → Online server** = `ws://HOST:47900`
* For release builds: set `DEFAULT_SERVER` in `game/src/net/party.gd` and rebuild.

Without a server the game still works: friends over Wi-Fi (LAN rooms), and PLAY searches briefly, then fills the match with bots.

## Test locally
`./mm_e2e.sh 5` (repo root) starts the matchmaker + two headless clients: room by code → queue → match with bots.

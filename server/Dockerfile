# MAYDON online server: matchmaker (WebSocket, TCP 47900) + dedicated matches (ENet, UDP 47910-47990).
# Build from the repo root:  docker build -f server/Dockerfile -t maydon-server .
# Run:   docker run -d --name maydon --restart unless-stopped -p 47900:47900/tcp -p 47910-47990:47910-47990/udp maydon-server
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends wget unzip ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*
RUN wget -q https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip -O /tmp/g.zip \
    && unzip /tmp/g.zip -d /opt && mv /opt/Godot_v4.7-stable_linux.x86_64 /usr/local/bin/godot && rm /tmp/g.zip
COPY game /game
RUN rm -rf /game/android /game/build && godot --headless --path /game --import >/dev/null 2>&1 || true
EXPOSE 47900/tcp
EXPOSE 47910-47990/udp
CMD ["godot", "--headless", "--path", "/game", "res://scenes/server.tscn", "--", "--mm", "port=47900", "match_ports=47910-47990"]

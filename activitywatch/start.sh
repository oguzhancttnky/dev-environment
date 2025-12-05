#!/bin/bash
cd ~/.local/opt/activitywatch
./aw-watcher-afk/aw-watcher-afk &
./aw-watcher-window/aw-watcher-window &
notify-send "ActivityWatch started"
./aw-server/aw-server;

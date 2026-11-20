SO BASICALLY, I USED MY PRIOR CODE FROM BASH_DESKTOP, which btw is not done, i wanted to get the 1.1x mult, and im gonna use it to make a serverwatch/scanner for my macbook homelab :D

HOW TO USE ( u need bash 5 or newer and UTF 8 terminal)
Basically this is a dashboard to see your homeservers stats, it has a live screen with CPU, Memory, Download / Upload graphs, busiest processes, listening ports, service checks, and an alert list.

--once prints only one reading
--daemon watches with no gui

setup:

git clone https://github.com/prestonbliang/serverwatch.git

cd serverwatch

bin/serverwatch

To run from anywhere, add an alias:

echo "alias serverwatch=$HOME/serverwatch/bin/serverwatch" >> ~/.zshrc

#commands
serverwatch
serverwatch --once
serverwatch --daemon

#CONFIG
you can change the point at which you get alerted for stuff

#to run on your server
SSH in, clone, make a config file, and keep a watcher running with --daemon

#to save as a systemd service that restarts itself

Save as `/etc/systemd/system/serverwatch.service` and replace `YOU` with your username:

    [Unit]
    Description=serverwatch

    [Service]
    User=YOU
    Environment=HOME=/home/YOU
    ExecStart=/home/YOU/serverwatch/bin/serverwatch --daemon
    Restart=always

    [Install]
    WantedBy=multi-user.target

then: 
    sudo systemctl daemon-reload
    sudo systemctl enable --now serverwatch


#cool way to get live alerts via Discord

serverwatch can post alerts into a Discord channel

1: make a webhook
In discord, open channel where you want alerts

CLICK THE GEAR ICON(EDIT CHANNEL)
GO TO INTEGRATIONS THEN WEBHOOKS
CLICK COPY WEBHOOK URL

2: check URL works
Run this command in a terminal with the URL you got
curl -H 'Content-Type: application/json' -d '{"content":"test from serverwatch"}' "PASTE_YOUR_URL_HERE"

3: Put it in your config file

Open serverwatch.conf and set WEBHOOK to the URL you got

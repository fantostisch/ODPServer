# Deploying your own server

## Prerequisites

### Dependencies

Your server will need to have CA certificates on your server. On Debian these can be installed with:

```sh
sudo apt-get install ca-certificates
```

### WebServer for TLS

Because [justdancenow.com](https://justdancenow.com) uses HTTPS, your server has to support a secure
connection. You can use NGINX to handle the secure connection.

Configure a webserver to handle TLS. [Example NGINX configuration](dance.example.vhost). To obtain a
certificate:

```sh
sudo certbot certonly -d dance.nickaquina.nl
```

### Setup

Do not run ODPServer as root, but create a new user:

```sh
sudo apt-get install adduser
sudo adduser --system --group --no-create-home odp-server
```

Create a file named `/etc/systemd/system/odp-server.service` with the following content:

```
[Unit]
Description=Onlline Dance Party Server
After=network.target

[Service]
ExecStart=/opt/ODPServer/ODPServer
Restart=on-failure
User=odp-server
Group=odp-server

[Install]
WantedBy=multi-user.target
```

Create a directory for ODPServer on the server:

```sh
sudo mkdir /opt/ODPServer
```

## Deploy / Update

```sh
# Build the project
cp doc/Settings.example.hs app/Settings.hs
stack build
# Copy the executable to the server and restart the service
scp "$(stack path --dist-dir)/build/ODPServer/ODPServer" "peter@dance.nickaquina.nl:~/ODPServer"
ssh peter@dance.nickaquina.nl "sudo mv ~/ODPServer /opt/ODPServer/ODPServer && sudo service odp-server restart"
```

Fill in your server address in the extension and have fun!

## Uninstall

```sh
sudo service odp-server stop
sudo delluser odp-server
sudo rm -rf /opt/ODPServer
sudo rm -f /etc/systemd/system/odp-server.service
# sudo apt-get remove ca-certificates adduser
```

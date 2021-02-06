# Deploying your own server

## Using docker image

todo: publish docker container on dockerhub

Because [justdancenow.com](https://justdancenow.com) uses HTTPS, your server has to support a secure
connection. You can use NGINX to handle the secure connection.

Configure a webserver to handle TLS. [Example NGINX configuration](dance.example.vhost). To
obtain a certificate:

```sh
sudo certbot certonly -d dance.nickaquina.nl
```

Build and deploy the docker container

```sh
# Build the docker container
stack build
docker build -t odp --build-arg dist_dir=$(stack path --dist-dir) .
# Copy the container to the server.
docker save odp | ssh peter@dance.nickaquina.nl "cat > ~/dance/odp.tar"
# SSH to the server
ssh peter@dance.nickaquina.nl
# Go to directory of docker image
cd ~/dance/
# Load the image on the server
docker load --input odp.tar
# Stop and remove existing container
docker stop odp && docker rm odp
# Run the docker container:
docker run --network host --restart=always --detach --name odp odp
```

Fill in your server address in the extension and have fun!

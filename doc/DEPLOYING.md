# Deploying your own server

## Using docker image

todo: publish docker container on dockerhub

Because [justdancenow.com](https://justdancenow.com) uses HTTPS, your server has to support a secure
connection. You can use NGINX to handle the secure connection.

Configure a webserver to handle TLS. [Example NGINX configuration](dance.example.vhost). To obtain a
certificate:

```sh
sudo certbot certonly -d dance.nickaquina.nl
```

Build and deploy the docker container

```sh
# Build the docker container
cp doc/Settings.example.hs app/Settings.hs
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

## Without docker (todo)

When compiling the program, it will be linked to the version of glibc currently installed. When the
version of glibc on the server is lower than the one used when compiling, the program will not
start. There was an attempt at static compilation in
the [static-build-remove-docker branch](https://github.com/fantostisch/ODPServer/tree/static-build-remove-docker),
but this results in a segfault. Other possible solutions:

* [Dynamically link to an older version of glibc](https://geekingfrog.com/blog/post/custom-glibc-haskell-binary).
* Compile inside a docker container
* Nix?
* [Use chroot](https://wiki.debian.org/chroot)

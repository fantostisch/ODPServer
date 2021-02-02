FROM ubuntu:20.04

LABEL Description="Image for Online Dance Party Server"

ARG dist_dir
ARG install_dir=/opt/ODPServer

EXPOSE 32623

RUN mkdir -p ${install_dir}
COPY ${dist_dir}/build/ODPServer/ODPServer ${install_dir}

RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y ca-certificates

WORKDIR ${install_dir}

CMD ["./ODPServer"]

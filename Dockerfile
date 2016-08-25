FROM ubuntu
MAINTAINER sukhchander <sukhchander@gmail.com>

RUN apt-get update
RUN apt-get install -y dnsutils netcat-traditional
RUN update-alternatives --set nc /bin/nc.traditional
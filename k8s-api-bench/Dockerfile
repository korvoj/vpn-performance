FROM ubuntu:22.04

RUN apt-get update && apt-get install -y wget && apt-get clean
RUN wget https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -O /usr/local/bin/hey && chmod +x /usr/local/bin/hey
COPY entrypoint.sh /

CMD ["/entrypoint.sh"]
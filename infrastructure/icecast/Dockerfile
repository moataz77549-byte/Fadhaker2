FROM alpine:3.19

RUN apk add --no-cache icecast mailcap

COPY icecast.xml /etc/icecast.xml
RUN chown -R icecast:icecast /etc/icecast.xml /var/log/icecast

USER icecast
EXPOSE 8000
CMD ["icecast", "-c", "/etc/icecast.xml"]

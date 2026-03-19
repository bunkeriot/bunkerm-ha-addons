FROM bunkeriot/bunkerm:latest

# jq is needed to parse /data/options.json from HA Supervisor
RUN apk add --no-cache jq

# Copy startup shim
COPY rootfs/init.sh /init.sh
RUN chmod +x /init.sh

EXPOSE 2000 1883

CMD ["/init.sh"]

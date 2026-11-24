# ProjectSend for Railway.
# Official image, pinned by version and digest. Bump both together and add a
# CHANGELOG.md entry: a merge to main notifies everyone who deployed the template.
FROM projectsend/projectsend:2.10.0@sha256:0bfc683524714f9d655efc683214052c4581a01e13a63c95fbb9c2c9819bfeef

# Upstream's entrypoint only migrates and creates the first administrator when
# it is asked to start "supervisord". Teach it our supervising wrapper's name
# too, and fail the build if upstream changes that line.
RUN sed -i 's#^if \[ "\$1" = "supervisord" \]#if [ "$1" = "railway-supervise" ] || [ "$1" = "supervisord" ]#' /usr/local/bin/projectsend-entrypoint \
    && grep -q '"\$1" = "railway-supervise"' /usr/local/bin/projectsend-entrypoint

COPY railway-start.sh /usr/local/bin/railway-start
COPY railway-supervise.sh /usr/local/bin/railway-supervise
RUN chmod 755 /usr/local/bin/railway-start /usr/local/bin/railway-supervise

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["railway-start"]

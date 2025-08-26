FROM postgres:18

ENV POSTGRES_USER=admin
ENV POSTGRES_PASSWORD=default
ENV POSTGRES_DB=db
ENV POSTGRES_INITDB_ARGS="--data-checksums"

VOLUME /var/lib/postgresql/data

EXPOSE 5432

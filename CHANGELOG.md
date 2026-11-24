# Changelog

## 2.10.0 (2026-11-24)

First release of the template.

- ProjectSend 2.10.0, official image `projectsend/projectsend:2.10.0@sha256:0bfc683524714f9d655efc683214052c4581a01e13a63c95fbb9c2c9819bfeef` (PHP 8.4.28).
- Services: ProjectSend (built from this repo), Railway MySQL (128 MB InnoDB buffer pool) and Railway Redis, each with a volume.
- The first administrator is created on the first boot from `ADMIN_EMAIL` and a generated `ADMIN_PASSWORD`, so the web setup screen is never open to the public.
- Listens on `PORT`; health check `/up`; nginx, PHP-FPM and queue workers sized from the service's memory and CPU limits; exits non-zero when nginx, PHP-FPM or supervisord stops, so Railway restarts it.

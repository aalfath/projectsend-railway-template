[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/projectsend?utm_medium=integration&utm_source=button&utm_campaign=projectsend)

# ProjectSend on Railway

One-click [ProjectSend](https://github.com/projectsend/projectsend) for [Railway](https://railway.com): a self-hosted portal for sending files to your clients. You upload a file, choose which clients or groups can see it, and each client signs in to a private page to download it.

**Version:** ProjectSend 2.10.0, from the official image `projectsend/projectsend:2.10.0`, pinned by digest in the [`Dockerfile`](Dockerfile).

## What the template deploys

| Service | What it does | Volume |
|---|---|---|
| **ProjectSend** (built from this repo) | nginx, PHP-FPM, the queue worker and the scheduler in one container (upstream's official layout). Public URL, health check `/up`. | `/var/www/html/storage`: uploaded files and the generated `APP_KEY` |
| **MySQL** (Railway's MySQL) | Accounts, clients, groups, permissions, share links, activity log. InnoDB buffer pool set to 128 MB. | `/var/lib/mysql` |
| **Redis** (Railway's Redis) | Sessions, cache and the job queue (notification emails, zip downloads). | `/data` |

The services talk over Railway's private network with reference variables. No password is fixed in the template.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `ADMIN_EMAIL` | *(you enter it)* | Email of the first administrator. You sign in with it. |
| `ADMIN_PASSWORD` | `${{secret(24)}}` | Generated password of the first administrator. Read it in the ProjectSend service's **Variables** tab. |
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Used in download links and emails. Change it if you add your own domain. |
| `DB_*`, `REDIS_*` | references to the MySQL and Redis services | Leave as they are. |
| `PORT` | `8080` | Port nginx listens on. |

The administrator is created on the first boot only. Changing `ADMIN_EMAIL` or `ADMIN_PASSWORD` later does nothing: change the password in ProjectSend (your profile), not in Railway.

## After deploying

1. Open the public URL and sign in with `ADMIN_EMAIL` and the generated `ADMIN_PASSWORD`.
2. Set up email under **System → Settings → Email** (it has a "send test" button). Until you do, ProjectSend writes emails to its log instead of sending them, so invitations and password resets won't arrive.
3. Add clients and groups, then upload files and assign them.

Optional: S3-compatible storage, LDAP, single sign-on and virus scanning (ClamAV) are configured in the app's settings. The ClamAV service upstream offers is not part of this template, because it needs more than 1 GB of RAM on its own.

## Resources

The ProjectSend service sizes itself from its memory limit at start:

- **Below 900 MB** (Railway's Free and Trial plans give 0.5 GB): PHP-FPM up to 4 workers on demand, PHP `memory_limit` 192 MB, and one queue worker serving the default, zips and scans queues in turn. It idles at about 140 MB. Tested at 0.5 GB / 1 vCPU.
- **900 MB and up:** more PHP workers and upstream's three separate queue workers.
- nginx starts one worker per CPU the service may use (not per host CPU).

Single uploads go through in 100 MB chunks, so large files work at any size.

If nginx, PHP-FPM or supervisord stops for good, the container exits with an error and Railway's restart policy starts it again.

## Updates

This repo pins an exact ProjectSend release. When a new release is out, we bump the pin here and add a [`CHANGELOG.md`](CHANGELOG.md) entry, breaking changes first. Railway then shows everyone who deployed the template an "update available" notice, and you choose when to apply it. Database migrations run on their own at start.

Back up the `/var/www/html/storage` volume and the MySQL volume before big upgrades. The storage volume holds both your files and `APP_KEY`, which decrypts saved SMTP and LDAP passwords.

## Licence

ProjectSend is GPL-2.0-or-later ([upstream licensing](https://github.com/projectsend/projectsend/blob/main/LICENSING.md)). The wrapper files in this repo (Dockerfile and start scripts) are under the MIT licence in [`LICENSE`](LICENSE).

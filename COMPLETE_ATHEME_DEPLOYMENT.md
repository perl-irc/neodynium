# Complete Atheme Services Deployment

## Current Status

The Atheme services container is running but showing "no uplinks configured" because it's missing the required environment variables for IRC server connections.

## Required Action

Run this command on the `magnet-atheme` server (SSH via Tailscale: `ssh root@magnet-atheme.camel-kanyu.ts.net`):

```bash
# Stop existing container
docker stop magnet-atheme
docker rm magnet-atheme

# Start with full configuration
docker run -d --name magnet-atheme \
  --restart unless-stopped \
  --network container:magnet-atheme-tailscale \
  -e SERVER_NAME=magnet-atheme \
  -e TAILSCALE_DOMAIN=camel-kanyu.ts.net \
  -e SERVICES_PASSWORD=vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj \
  -e ADMIN_NAME="Chris Prather" \
  -e ADMIN_EMAIL="chris@prather.org" \
  -e ATHEME_NETWORK=Magnet \
  -e ATHEME_HUB_HOSTNAME=magnet-9rl.camel-kanyu.ts.net \
  -e ATHEME_FALLBACK_HOSTNAME=magnet-1eu.camel-kanyu.ts.net \
  -e PASSWORD_9RL=vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj \
  -e PASSWORD_1EU=vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj \
  magnet-atheme-services

# Check logs
docker logs magnet-atheme --tail 20
```

## Expected Outcome

After running this command, Atheme should connect to the IRC servers and you should see log messages like:

```
[timestamp] Connected to uplink magnet-9rl.camel-kanyu.ts.net
[timestamp] Introducing service NickServ
[timestamp] Introducing service ChanServ
[timestamp] Introducing service OperServ
[timestamp] Introducing service MemoServ
```

## Configuration Details

The configuration establishes:

- **Primary uplink**: `magnet-9rl.camel-kanyu.ts.net` (US Hub)
- **Fallback uplink**: `magnet-1eu.camel-kanyu.ts.net` (EU Leaf) 
- **Services**: NickServ, ChanServ, OperServ, MemoServ
- **Database**: OpenSEX flat file (no PostgreSQL needed)
- **Networking**: Via Tailscale mesh (`magnet-atheme.camel-kanyu.ts.net`)

## Alternative Script Method

You can also copy `restart-atheme.sh` to the server and run it:

```bash
scp restart-atheme.sh root@magnet-atheme.camel-kanyu.ts.net:~/
ssh root@magnet-atheme.camel-kanyu.ts.net
chmod +x restart-atheme.sh
./restart-atheme.sh
```

## Verification

Once complete, test IRC services functionality:

1. Connect to IRC: `/connect magnet-9rl.camel-kanyu.ts.net 6667`
2. Register nickname: `/msg NickServ REGISTER password email`
3. Join channel: `/join #test`
4. Register channel: `/msg ChanServ REGISTER #test`

The migration from Fly.io to DigitalOcean will be complete once Atheme connects successfully.
Pull latest:
```shell
git pull origin master
```

List docker secrets:
```shell
docker secret ls
```

Remove docker secret:
```shell
docker secret rm <secret_name>
```

Stop docker compose and remove volumes:
```shell
sudo docker compose down -v
```

Running backend only – restart:
```shell
sudo docker compose up -d --no-deps --force-recreate --build primrose-backend
```

Deploy stack (Swarm) using the convenience script (recommended):
```shell
# run from repo root on the server
sudo ./deploy.sh
```

Create or re-create secrets from the server's PrimroseBackend/.env (the deploy script will try to auto-create missing secrets):
```shell
# interactive creation example
read -s -p "Enter JwtSecret: " JWT && echo
printf '%s' "$JWT" | docker secret create primrose_jwt -

read -s -p "Enter SharedSecret: " SH && echo
printf '%s' "$SH" | docker secret create primrose_shared -
```

Confirm active swarm mode:  
```shell
docker info --format '{{.Swarm.LocalNodeState}}'
```
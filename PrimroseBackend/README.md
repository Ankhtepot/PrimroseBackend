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
sudo docker compose up -d --no-deps --force-recreate --build primrose-backend`
```

Confirm active swarm mode:  
```shell
docker info --format '{{.Swarm.LocalNodeState}}'
```
#!/bin/bash
eval $(bash dotenv export)
docker tag gtgt/mysql8-alpine:${MYSQL_VERSION} gitlab.oneincsystems.com:5050/claimspay3/v3.2/mysql8-alpine:${MYSQL_VERSION}
docker push gitlab.oneincsystems.com:5050/claimspay3/v3.2/mysql8-alpine:${MYSQL_VERSION}

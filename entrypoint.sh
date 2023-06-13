#!/bin/sh

set -euo pipefail

# set default values
readonly MYSQL_DATABASE="${MYSQL_DATABASE:-}"
readonly MYSQL_USER="${MYSQL_USER:-}"
readonly MYSQL_ROOT_HOST="${MYSQL_ROOT_HOST:-localhost}"
readonly MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
readonly MYSQL_CHARSET="${MYSQL_CHARSET:-utf8}"
readonly MYSQL_COLLATION="${MYSQL_COLLATION:-utf8_general_ci}"

getconf() {
	local v=$(my_print_defaults --mysqld | grep ^--"$1")
	[ -z "$v" ] && echo "$2" || echo "${v#*=}"
}

genpass() {
	tr -cd '[:alnum:]' < /dev/urandom | fold -w16 | head -n1
}

readonly MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(genpass)}"
readonly MYSQL_DATADIR=$(getconf datadir "/var/lib/mysql" 2>/dev/null)
readonly MYSQL_SOCKET=$(getconf socket "/var/run/mysqld/mysqld.sock" 2>/dev/null)

init_db() {
	cat <<- EOF
	SET @@SESSION.SQL_LOG_BIN=0;
	ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
	DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
	DROP DATABASE IF EXISTS test;
	FLUSH PRIVILEGES;
	EOF

	# create database if requested
	if [ "$MYSQL_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` CHARACTER SET $MYSQL_CHARSET COLLATE $MYSQL_COLLATION;"
	fi

	# create user if requested
	if [ "$MYSQL_DATABASE" ] && [ "$MYSQL_USER" ] && [ "$MYSQL_PASSWORD" ]; then
		echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' GRANT ALL ON \`$MYSQL_DATABASE\`.* to '$MYSQL_USER'@'%';"
	fi

	echo "FLUSH PRIVILEGES;"
}

# make sure these directories exist with correct user
install -d -o mysql -g mysql "${MYSQL_SOCKET%/*}" "$MYSQL_DATADIR"

if [ ! -d "/var/lib/mysql/mysql" ]; then

	# create a defaults file for root user for save password usage
	MYSQL_ROOT_DEFAULTS_FILE=$(mktemp)
	cat <<- EOF > "$MYSQL_ROOT_DEFAULTS_FILE"
	[client]
	user=root
	password="${MYSQL_ROOT_PASSWORD}"
	EOF

	# install initial database
	mysqld --initialize-insecure --user=mysql --datadir="$MYSQL_DATADIR" > /dev/null

	# starting temporary mysql server in the background
	mysqld --skip-networking --user=mysql > /dev/null &

	# wait until database is really up
	while ! mysql --user=root --database=mysql --execute="SELECT 1" >/dev/null 2>&1; do
		sleep 1
	done

	# initialize db and permissions (needs root password afterwards)
	init_db | mysql --user=root

	# install any initial database dumps
	for f in /docker-entrypoint-initdb.d/*; do
		[ ! -f "$f" ] && continue
		echo "Starting to import sql file: $f"
		case "$f" in
			*.sql) mysql --defaults-file="$MYSQL_ROOT_DEFAULTS_FILE" --database="$MYSQL_DATABASE" < "$f" ;;
			*.sql.gz) zcat "$f" | mysql --defaults-file="$MYSQL_ROOT_DEFAULTS_FILE" --database="$MYSQL_DATABASE" ;;
			*) echo "$f: is not a .sql or .sql.gz file. Skipping.." ;;
		esac
	done

	# gracefully shutdown temporary server
	mysqladmin --defaults-file="$MYSQL_ROOT_DEFAULTS_FILE" shutdown > /dev/null

	rm -f "$MYSQL_ROOT_DEFAULTS_FILE"

	printf "The root password is set to: %s \n\n" "$MYSQL_ROOT_PASSWORD"

fi

# here we go!
echo "Starting MySQLD with arguments: $@"
exec mysqld --user=mysql $@


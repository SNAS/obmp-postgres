# OpenBMP PostgreSQL

Postgres Install
----------------
You will need a postgres server.  You **MUST** use PostgreSQL **10.x** or greater.  

Follow the install intructions under [PostgreSQL Download](https://www.postgresql.org/download/) to install.


#### Example Installing Postgres 10.x on Ubuntu 10.x

```sh
echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main" > /etc/apt/sources.list.d/pgdg.list

wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

sudo apt-get update

sudo apt-get install postgresql-10
```

Postgres Configuration
----------------------
You will need to create the **openbmp** user and database.  You also should adjust/tune the memory
settings. 

TBD - add details here



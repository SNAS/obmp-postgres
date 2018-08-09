-- -----------------------------------------------------------------------
-- Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
--
-- BEGIN Base Schema
-- -----------------------------------------------------------------------

-- SET TIME ZONE 'UTC';

-- enable timescale DB
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Use different disk for history/log/time series
CREATE TABLESPACE timeseries LOCATION '/data1/postgres/ts';


-- -----------------------------------------------------
-- Enums used in tables
-- -----------------------------------------------------
CREATE TYPE opState as enum ('up', 'down', '');
CREATE TYPE user_role as enum ('admin', 'oper', '');

-- -----------------------------------------------------
-- Tables and base, non dependant functions
-- -----------------------------------------------------

-- Table structure for table geo_ip
DROP TABLE IF EXISTS geo_ip;
CREATE TABLE geo_ip (
  family                smallint        NOT NULL,
  ip_start              inet            NOT NULL,
  ip_end                inet            NOT NULL,
  country               char(2)         NOT NULL,
  stateprov             varchar(80)     NOT NULL,
  city                  varchar(80)     NOT NULL,
  latitude              float           NOT NULL,
  longitude             float           NOT NULL,
  timezone_offset       float           NOT NULL,
  timezone_name         varchar(64)     NOT NULL,
  isp_name              varchar(128)    NOT NULL,
  connection_type       varchar(64),
  organization_name     varchar(128),
  PRIMARY KEY (ip_start)
);
CREATE INDEX ON geo_ip (stateprov);
CREATE INDEX ON geo_ip (country);
CREATE INDEX ON geo_ip (family);
CREATE INDEX ON geo_ip (ip_end);
CREATE INDEX ON geo_ip (ip_start,ip_end);

INSERT INTO geo_ip VALUES
	(4, '0.0.0.0', '255.255.255.255', 'US', 'WA', 'Seattle', 47.6129432, -122.4821472, 0, 'UTC', 'default', 'default', 'default'),
	(6, '::', 'FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF', 'US', 'WA', 'Seattle', 47.6129432, -122.4821472, 0, 'UTC', 'default', 'default', 'default');

-- CREATE OR REPLACE FUNCTION find_geo_ip_start(ip inet)
--	RETURNS inet AS $$
--	DECLARE
--	        geo_ip_start inet := NULL;
--	BEGIN
--
--	    SELECT ip_start INTO geo_ip_start
--	    FROM geo_ip
--	    WHERE ip_end >= ip
--	          and ip_start <= ip and
--	          family = family(ip)
--	    ORDER BY ip_end limit 1;
--
--		RETURN geo_ip_start;
--	END;
--$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_geo_ip_start(ip inet)
	RETURNS inet AS $$
	    SELECT ip_start
		    FROM geo_ip
	        WHERE ip_end >= ip
	          and ip_start <= ip and
	          family = family(ip)
	        ORDER BY ip_end limit 1
	$$ LANGUAGE SQL;


-- Table structure for table rpki_validator
DROP TABLE IF EXISTS rpki_validator;
CREATE TABLE rpki_validator (
	prefix              inet            NOT NULL,
	prefix_len          smallint        NOT NULL DEFAULT 0,
	prefix_len_max      smallint        NOT NULL DEFAULT 0,
	origin_as           bigint          NOT NULL,
	timestamp           timestamp       without time zone default (now() at time zone 'utc') NOT NULL,
	PRIMARY KEY (prefix,prefix_len_max,origin_as)
);
CREATE INDEX ON rpki_validator (origin_as);
CREATE INDEX ON rpki_validator USING gist (prefix inet_ops);



-- Table structure for table users
--    note: change password to use crypt(), but change db_rest to support it
--
--    CREATE EXTENSION pgcrypto;
--             Create: crypt('new password', gen_salt('md5'));
--             Check:  select ...  WHERE password = crypt('user entered pw', password);
DROP TABLE IF EXISTS users;
CREATE TABLE users (
	username            varchar(50)     NOT NULL,
	password            varchar(50)     NOT NULL,
	type                user_role       NOT NULL,
	PRIMARY KEY (username)
);
INSERT INTO users (username,password,type) VALUES ('openbmp', 'openbmp', 'admin');


-- Table structure for table collectors
DROP TABLE IF EXISTS collectors;
CREATE TABLE collectors (
	hash_id             uuid                NOT NULL,
	state               opState             DEFAULT 'down',
	admin_id            varchar(64)         NOT NULL,
	routers             varchar(4096),
	router_count        smallint            NOT NULL DEFAULT 0,
	timestamp           timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	name                varchar(200),
	ip_address          varchar(40),
	PRIMARY KEY (hash_id)
);

-- Table structure for table routers
DROP TABLE IF EXISTS routers;
CREATE TABLE routers (
	hash_id             uuid                NOT NULL,
	name                varchar(200)        NOT NULL,
	ip_address          inet                NOT NULL,
	router_AS           bigint,
	timestamp           timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	description         varchar(255),
	state               opState             DEFAULT 'down',
	isPassive           boolean             DEFAULT false,
	term_reason_code    int,
	term_reason_text    varchar(255),
	term_data           text,
	init_data           text,
	geo_ip_start        inet,
	collector_hash_id   uuid                NOT NULL,
	bgp_id              inet,
	PRIMARY KEY (hash_id)
);


CREATE INDEX ON routers (name);
CREATE INDEX ON routers (ip_address);

-- Table structure for table bgp_peers
DROP TABLE IF EXISTS bgp_peers;
CREATE TABLE bgp_peers (
	hash_id                 uuid                NOT NULL,
	router_hash_id          uuid                NOT NULL,
	peer_rd                 varchar(32)         NOT NULL,
	isIPv4                  boolean             NOT NULL DEFAULT true,
	peer_addr               inet                NOT NULL,
	name                    varchar(200),
	peer_bgp_id             inet                NOT NULL,
	peer_as                 bigint              NOT NULL,
	state                   opState             NOT NULL DEFAULT 'down',
	isL3VPNpeer             boolean             NOT NULL DEFAULT false,
	timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	isPrePolicy             boolean             DEFAULT true,
	geo_ip_start            inet,
	local_ip                inet,
	local_bgp_id            inet,
	local_port              int,
	local_hold_time         smallint,
	local_asn               bigint,
	remote_port             int,
	remote_hold_time        smallint,
	sent_capabilities       varchar(4096),
	recv_capabilities       varchar(4096),
	bmp_reason              smallint,
	bgp_err_code            smallint,
	bgp_err_subcode         smallint,
	error_text              varchar(255),
	isLocRib                boolean             NOT NULL DEFAULT false,
	isLocRibFiltered        boolean             NOT NULL DEFAULT false,
	table_name              varchar(255),
	PRIMARY KEY (hash_id)
);

CREATE INDEX ON bgp_peers (peer_addr);
CREATE INDEX ON bgp_peers (name);
CREATE INDEX ON bgp_peers (peer_as);
CREATE INDEX ON bgp_peers (router_hash_id);

-- Table structure for table peer_event_log
--     updated by bgp_peers trigger
DROP TABLE IF EXISTS peer_event_log;
CREATE TABLE peer_event_log (
	id                  bigserial               NOT NULL,
	state               opState                 NOT NULL,
	peer_hash_id        uuid                    NOT NULL,
	local_ip            inet,
	local_bgp_id        inet,
	local_port          int,
	local_hold_time     int,
	local_asn           bigint,
	remote_port         int,
	remote_hold_time    int,
	sent_capabilities   varchar(4096),
	recv_capabilities   varchar(4096),
	bmp_reason          smallint,
	bgp_err_code        smallint,
	bgp_err_subcode     smallint,
	error_text          varchar(255),
	timestamp           timestamp(6)            without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON peer_event_log (peer_hash_id);
CREATE INDEX ON peer_event_log (local_ip);
CREATE INDEX ON peer_event_log (local_asn);

-- convert to timescaledb
SELECT create_hypertable('peer_event_log', 'timestamp');


-- Table structure for table stat_reports
--     TimescaleDB
DROP TABLE IF EXISTS stat_reports;
CREATE TABLE stat_reports (
	id                                  bigserial               NOT NULL,
	peer_hash_id                        uuid                    NOT NULL,
	prefixes_rejected                   bigint,
	known_dup_prefixes                  bigint,
	known_dup_withdraws                 bigint,
    updates_invalid_by_cluster_list     bigint,
    updates_invalid_by_as_path_loop     bigint,
    updates_invalid_by_originagtor_id   bigint,
    updates_invalid_by_as_confed_loop   bigint,
    num_routes_adj_rib_in               bigint,
    num_routes_local_rib                bigint,
    timestamp timestamp(6)              without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON stat_reports (peer_hash_id);

-- convert to timescaledb
SELECT create_hypertable('stat_reports', 'timestamp');

-- Table structure for table base_attrs
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/
DROP TABLE IF EXISTS base_attrs;
CREATE TABLE base_attrs (
	hash_id                 uuid                NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	origin                  varchar(16)         NOT NULL,
	as_path                 varchar(8192)       NOT NULL,
	as_path_count           smallint            DEFAULT 0,
    origin_as               bigint,
    next_hop                inet,
    med                     bigint,
    local_pref              bigint,
    aggregator              varchar(64),
    community_list          varchar(6000),
    ext_community_list      varchar(2048),
    large_community_list    varchar(3000),
    cluster_list            varchar(2048),
    isAtomicAgg             boolean             DEFAULT false,
    nexthop_isIPv4          boolean             DEFAULT true,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    originator_id           inet,
    PRIMARY KEY (hash_id)
);

CREATE INDEX ON base_attrs (origin_as);
CREATE INDEX ON base_attrs (as_path_count);
CREATE INDEX ON base_attrs (as_path);

-- Table structure for table rib
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/--
DROP TABLE IF EXISTS ip_rib;
CREATE TABLE ip_rib (
	hash_id                 uuid                NOT NULL,
    base_attr_hash_id       uuid,
    peer_hash_id            uuid                NOT NULL,
    isIPv4                  boolean             NOT NULL,
    origin_as               bigint,
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    first_added_timestamp   timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    isWithdrawn             boolean             NOT NULL DEFAULT false,
    prefix_bits             varchar(128),
    path_id                 bigint,
    labels                  varchar(255),
    isPrePolicy             boolean             NOT NULL DEFAULT true,
    isAdjRibIn              boolean             NOT NULL DEFAULT true,
    PRIMARY KEY (hash_id)
);

-- CREATE UNIQUE INDEX ON ip_rib (hash_id);
CREATE INDEX ON ip_rib (peer_hash_id);
CREATE INDEX ON ip_rib (base_attr_hash_id);
CREATE INDEX ON ip_rib USING GIST (prefix inet_ops);
CREATE INDEX ON ip_rib (isWithdrawn);
CREATE INDEX ON ip_rib (origin_as);
CREATE INDEX ON ip_rib (prefix_bits);


-- Table structure for table ip_rib_log
DROP TABLE IF EXISTS ip_rib_log;
CREATE TABLE ip_rib_log (
    id                      bigserial           NOT NULL,
	base_attr_hash_id       uuid                NOT NULL,
	timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    peer_hash_id            uuid                NOT NULL,
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL,
    origin_as               bigint              NOT NULL,
    isWithdrawn             boolean             NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON ip_rib_log (peer_hash_id);
CREATE INDEX ON ip_rib_log (prefix);
CREATE INDEX ON ip_rib_log (origin_as);

-- convert to timescaledb
SELECT create_hypertable('ip_rib_log', 'timestamp', chunk_time_interval => interval '5 day');


-- Table structure for global ip rib
DROP TABLE IF EXISTS global_ip_rib;
CREATE TABLE global_ip_rib (
    prefix                  inet                NOT NULL,
  	should_delete           boolean             NOT NULL DEFAULT false,
    prefix_len              smallint            NOT NULL DEFAULT 0,
    recv_origin_as          bigint              NOT NULL,
    rpki_origin_as          bigint,
    irr_origin_as           bigint,
    irr_source              varchar(32),
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,

    PRIMARY KEY (prefix,recv_origin_as)
);
CREATE INDEX ON global_ip_rib (recv_origin_as);
CREATE INDEX ON global_ip_rib USING GIST (prefix inet_ops);
CREATE INDEX ON global_ip_rib (should_delete);


-- Table structure for table info_asn (based on whois)
DROP TABLE IF EXISTS info_asn;
CREATE TABLE info_asn (
    asn                     bigint              NOT NULL,
    as_name                 varchar(255),
    org_id                  varchar(255),
    org_name                varchar(255),
    remarks                 text,
    address                 varchar(255),
    city                    varchar(255),
    state_prov              varchar(255),
    postal_code             varchar(255),
    country                 varchar(255),
    raw_output              text,
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,
    source                  varchar(64)         DEFAULT NULL,
    PRIMARY KEY (asn)
);

-- Table structure for table info_route (based on whois)
DROP TABLE IF EXISTS info_route;
CREATE TABLE info_route (
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL DEFAULT 0,
    descr                   text,
    origin_as               bigint              NOT NULL,
    source                  varchar(32)         NOT NULL,
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,
    PRIMARY KEY (prefix,prefix_len,origin_as)
);
CREATE INDEX ON info_route (origin_as);


-- Table structure for table as_path_analysis
--     Optionally enabled table to index AS paths
DROP TABLE IF EXISTS as_path_analysis;
CREATE TABLE as_path_analysis (
    asn                     bigint              NOT NULL,
    asn_left                bigint              NOT NULL DEFAULT 0,
    asn_right               bigint              NOT NULL DEFAULT 0,
    asn_left_is_peering     boolean             DEFAULT false,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    PRIMARY KEY (asn,asn_left_is_peering,asn_left,asn_right)
);

CREATE INDEX ON as_path_analysis (asn_left);
CREATE INDEX ON as_path_analysis (asn_right);

-- Alerts table for security monitoring
DROP TABLE IF EXISTS alerts;
CREATE TABLE alerts (
	id                      bigserial           NOT NULL,
    type                    varchar(128)        NOT NULL,
	message                 text                NOT NULL,
    monitored_asn           bigint,
    offending_asn           bigint,
    monitored_asname        varchar(200),
    offending_asname        varchar(200),
	affected_prefix         inet,
	history_url             varchar(512),
	event_json              jsonb,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;

CREATE INDEX ON alerts (monitored_asn);
CREATE INDEX ON alerts (offending_asn);
CREATE INDEX ON alerts (type);
CREATE INDEX ON alerts (affected_prefix);

-- convert to timescaledb
SELECT create_hypertable('alerts', 'timestamp');


--
-- END
--

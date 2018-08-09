-- -----------------------------------------------------------------------
-- Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
--
-- BEGIN Views Schema
-- -----------------------------------------------------------------------


drop view IF EXISTS v_peers;
CREATE VIEW v_peers AS
SELECT CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE  host(rtr.ip_address) END AS RouterName, rtr.ip_address as RouterIP,
                p.local_ip as LocalIP, p.local_port as LocalPort, p.local_asn as LocalASN, p.local_bgp_id as LocalBGPId,
                CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
                p.peer_addr as PeerIP, p.remote_port as PeerPort, p.peer_as as PeerASN,
                p.peer_bgp_id as PeerBGPId,
                p.local_hold_time as LocalHoldTime, p.remote_hold_time as PeerHoldTime,
                p.state as peer_state, rtr.state as router_state,
                p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN, p.isPrePolicy as isPrePolicy,
                p.timestamp as LastModified,
                p.bmp_reason as LastBMPReasonCode, p.bgp_err_code as LastDownCode,
                p.bgp_err_subcode as LastdownSubCode, p.error_text as LastDownMessage,
                p.timestamp as LastDownTimestamp,
                p.sent_capabilities as SentCapabilities, p.recv_capabilities as RecvCapabilities,
                w.as_name,
                p.isLocRib,p.isLocRibFiltered,p.table_name,
                p.hash_id as peer_hash_id, rtr.hash_id as router_hash_id,p.geo_ip_start

        FROM bgp_peers p JOIN routers rtr ON (p.router_hash_id = rtr.hash_id)
                                         LEFT JOIN info_asn w ON (p.peer_as = w.asn);

drop view IF EXISTS v_ip_routes;
CREATE  VIEW v_ip_routes AS
       SELECT  CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE host(rtr.ip_address) END AS RouterName,
                CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
                r.prefix AS Prefix,r.prefix_len AS PrefixLen,
                attr.origin AS Origin,r.origin_as AS Origin_AS,attr.med AS MED,
                attr.local_pref AS LocalPref,attr.next_hop AS NH,attr.as_path AS AS_Path,
                attr.as_path_count AS ASPath_Count,attr.community_list AS Communities,
                attr.ext_community_list AS ExtCommunities,attr.large_community_list AS LargeCommunities,
                attr.cluster_list AS ClusterList,
                attr.aggregator AS Aggregator,p.peer_addr AS PeerAddress, p.peer_as AS PeerASN,r.isIPv4 as isIPv4,
                p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN,
                r.timestamp AS LastModified, r.first_added_timestamp as FirstAddedTimestamp,
                r.path_id, r.labels,
                r.hash_id as rib_hash_id,
                r.base_attr_hash_id as base_hash_id, r.peer_hash_id, rtr.hash_id as router_hash_id,r.isWithdrawn,
                r.prefix_bits,r.isPrePolicy,r.isAdjRibIn
        FROM bgp_peers p JOIN ip_rib r ON (r.peer_hash_id = p.hash_id)
            JOIN base_attrs attr ON (attr.hash_id = r.base_attr_hash_id and attr.peer_hash_id = r.peer_hash_id)
            JOIN routers rtr ON (p.router_hash_id = rtr.hash_id);

drop view IF EXISTS v_ip_routes_history;
CREATE VIEW v_ip_routes_history AS
  SELECT
             CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE host(rtr.ip_address) END AS RouterName,
            rtr.ip_address as RouterAddress,
	        CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
            log.prefix AS Prefix,log.prefix_len AS PrefixLen,
            attr.origin AS Origin,log.origin_as AS Origin_AS,
            attr.med AS MED,attr.local_pref AS LocalPref,attr.next_hop AS NH,
            attr.as_path AS AS_Path,attr.as_path_count AS ASPath_Count,attr.community_list AS Communities,
            attr.ext_community_list AS ExtCommunities,attr.large_community_list AS LargeCommunities,
            attr.cluster_list AS ClusterList,attr.aggregator AS Aggregator,p.peer_addr AS PeerIp,
            p.peer_as AS PeerASN,  p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN,
            log.id,log.timestamp AS LastModified,
            CASE WHEN log.iswithdrawn THEN 'Withdrawn' ELSE 'Advertised' END as event,
            log.base_attr_hash_id as base_attr_hash_id, log.peer_hash_id, rtr.hash_id as router_hash_id
        FROM ip_rib_log log
            JOIN base_attrs attr
                        ON (log.base_attr_hash_id = attr.hash_id AND
                            log.peer_hash_id = attr.peer_hash_id)
            JOIN bgp_peers p ON (log.peer_hash_id = p.hash_id)
            JOIN routers rtr ON (p.router_hash_id = rtr.hash_id);


--
-- END
--

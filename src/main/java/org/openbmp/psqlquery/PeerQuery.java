/*
 * Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 *
 */
package org.openbmp.psqlquery;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.openbmp.api.parsed.message.MsgBusFields;

public class PeerQuery extends Query{
	
	public PeerQuery(List<Map<String, Object>> rowMap){
		
		this.rowMap = rowMap;
	}
	
	
    /**
     * Generate MySQL insert/update statement, sans the values
     *
     * @return Two strings are returned
     *      0 = Insert statement string up to VALUES keyword
     *      1 = ON DUPLICATE KEY UPDATE ...  or empty if not used.
     */
    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO bgp_peers (hash_id,router_hash_id,peer_rd,isIPv4,peer_addr,name,peer_bgp_id," +
                           "peer_as,state,isL3VPNpeer,timestamp,isPrePolicy,local_ip,local_bgp_id,local_port," +
                           "local_hold_time,local_asn,remote_port,remote_hold_time,sent_capabilities," +
                           "recv_capabilities,bmp_reason,bgp_err_code,bgp_err_subcode,error_text," +
                           "isLocRib,isLocRibFiltered,table_name) " +
                            " VALUES ",

                           " ON CONFLICT (hash_id) DO UPDATE SET name=excluded.name,state=excluded.state," +
                                   "timestamp=excluded.timestamp,local_port=excluded.local_port," +
                                   "local_hold_time=excluded.local_hold_time,remote_port=excluded.remote_port," +
                                   "remote_hold_time=excluded.remote_hold_time,sent_capabilities=excluded.sent_capabilities," +
                                   "recv_capabilities=excluded.recv_capabilities,bmp_reason=excluded.bmp_reason," +
                                   "bgp_err_code=excluded.bgp_err_code,bgp_err_subcode=excluded.bgp_err_subcode," +
                                   "error_text=excluded.error_text,table_name=excluded.table_name" };
        return stmt;
    }

    /**
     * Generate bulk values statement for SQL bulk insert.
     *
     * @return String in the format of (col1, col2, ...)[,...]
     */
    public String genValuesStatement() {
        StringBuilder sb = new StringBuilder();

        for (int i=0; i < rowMap.size(); i++) {
            if (i > 0)
                sb.append(',');

            sb.append('(');
            sb.append("'" + lookupValue(MsgBusFields.HASH, i) + "'::uuid,");
            sb.append("'" + lookupValue(MsgBusFields.ROUTER_HASH, i) + "'::uuid,");
            sb.append("'" + lookupValue(MsgBusFields.PEER_RD, i) + "',");
            sb.append(lookupValue(MsgBusFields.IS_IPV4, i) + "::boolean,");
            sb.append("'" + lookupValue(MsgBusFields.REMOTE_IP, i) + "'::inet,");
            sb.append("'" + lookupValue(MsgBusFields.NAME, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.REMOTE_BGP_ID, i) + "'::inet,");
            sb.append(lookupValue(MsgBusFields.REMOTE_ASN, i) + ",");

            sb.append("'" + (((String)lookupValue(MsgBusFields.ACTION, i)).equalsIgnoreCase("up") ? "up" : "down") + "',");

            sb.append(lookupValue(MsgBusFields.IS_L3VPN, i) + "::boolean,");
            sb.append("'" + lookupValue(MsgBusFields.TIMESTAMP, i) + "'::timestamp,");
            sb.append(lookupValue(MsgBusFields.ISPREPOLICY, i) + "::boolean,");

            if (((String)lookupValue(MsgBusFields.LOCAL_IP, i)).length() > 2)
                sb.append("'" + lookupValue(MsgBusFields.LOCAL_IP, i) + "'::inet,");
            else
                sb.append("null,");

            if (((String)lookupValue(MsgBusFields.LOCAL_BGP_ID, i)).length() > 2)
                sb.append("'" + lookupValue(MsgBusFields.LOCAL_BGP_ID, i) + "'::inet,");
            else
                sb.append("null,");

            sb.append(lookupValue(MsgBusFields.LOCAL_PORT, i) + ",");
            sb.append(lookupValue(MsgBusFields.ADV_HOLDDOWN, i) + ",");
            sb.append(lookupValue(MsgBusFields.LOCAL_ASN, i) + ",");
            sb.append(lookupValue(MsgBusFields.REMOTE_PORT, i) + ",");
            sb.append(lookupValue(MsgBusFields.REMOTE_HOLDDOWN, i) + ",");
            sb.append("'" + lookupValue(MsgBusFields.ADV_CAP, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.RECV_CAP, i) + "',");
            sb.append(lookupValue(MsgBusFields.BMP_REASON, i) + ",");
            sb.append(lookupValue(MsgBusFields.BGP_ERROR_CODE, i) + ",");
            sb.append(lookupValue(MsgBusFields.BGP_ERROR_SUB_CODE, i) + ",");
            sb.append("'" + lookupValue(MsgBusFields.ERROR_TEXT, i) + "',");
            sb.append(lookupValue(MsgBusFields.IS_LOCRIB, i) + "::boolean,");
            sb.append(lookupValue(MsgBusFields.IS_LOCRIB_FILTERED, i) + "::boolean,");
            sb.append("'" + lookupValue(MsgBusFields.TABLE_NAME, i) + "'");
            sb.append(')');
        }

        return sb.toString();
    }


    /**
     * Generate SQL RIB update statement to withdraw all rib entries
     *
     * Upon peer up or down, withdraw all RIB entries.  When the PEER is up all
     *   RIB entries will get updated.  Depending on how long the peer was down, some
     *   entries may not be present anymore, thus they are withdrawn.
     *
     * @return  List of query strings to execute
     */
    public List<String> genRibPeerUpdate() {
        List<String> result = new ArrayList<>();

        for (int i=0; i < rowMap.size(); i++) {
            StringBuilder sb = new StringBuilder();

            //sb.append("UPDATE ip_rib SET isWithdrawn = true WHERE peer_hash_id = '");
            sb.append("DELETE FROM ip_rib WHERE peer_hash_id = '");
            sb.append(lookupValue(MsgBusFields.HASH, i));
            sb.append("' AND timestamp < '");
            sb.append(rowMap.get(i).get(MsgBusFields.TIMESTAMP.getName()) + "'");

//            sb.append("; UPDATE ls_nodes SET isWithdrawn = True WHERE peer_hash_id = '");
//            sb.append(lookupValue(MsgBusFields.HASH, i));
//            sb.append("' AND timestamp < '");
//            sb.append(rowMap.get(i).get(MsgBusFields.TIMESTAMP.getName()) + "'");

//            sb.append("; UPDATE ls_links SET isWithdrawn = True WHERE peer_hash_id = '");
//            sb.append(lookupValue(MsgBusFields.HASH, i));
//            sb.append("' AND timestamp < '");
//            sb.append(rowMap.get(i).get(MsgBusFields.TIMESTAMP.getName()) + "'");
//
//            sb.append("; UPDATE ls_prefixes SET isWithdrawn = True WHERE peer_hash_id = '");
//            sb.append(lookupValue(MsgBusFields.HASH, i));
//            sb.append("' AND timestamp < '");
//            sb.append(rowMap.get(i).get(MsgBusFields.TIMESTAMP.getName()) + "'");

            result.add(sb.toString());
        }

        return result;
    }

}

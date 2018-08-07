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
import java.util.concurrent.ConcurrentHashMap;

import org.openbmp.RouterObject;
import org.openbmp.api.parsed.message.MsgBusFields;
import org.openbmp.api.parsed.message.Message;

public class RouterQuery extends Query{
	
	
	private Message message; 
	
	public RouterQuery(Message message, List<Map<String, Object>> rowMap){
		
		this.rowMap = rowMap;
		this.message = message;
	}
	
    /**
     * Generate MySQL insert/update statement, sans the values
     *
     * @return Two strings are returned
     *      0 = Insert statement string up to VALUES keyword
     *      1 = ON DUPLICATE KEY UPDATE ...  or empty if not used.
     */
    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO routers (hash_id,name,ip_address,timestamp,state,term_reason_code," +
                                  "term_reason_text,term_data,init_data,description,collector_hash_id,bgp_id) " +
                            " VALUES ",

                            " ON CONFLICT (hash_id) DO UPDATE SET timestamp=excluded.timestamp,state=excluded.state," +
                                   "name=CASE excluded.state WHEN 'up' THEN excluded.name ELSE routers.name END," +
                                   "description=CASE excluded.state WHEN 'up' THEN excluded.description ELSE routers.description END," +
                                   "bgp_id=excluded.bgp_id," +
                                   "init_data=CASE excluded.state WHEN 'up' THEN excluded.init_data ELSE routers.init_data END," +
                                   "term_reason_code=excluded.term_reason_code,term_reason_text=excluded.term_reason_text," +
                                   "collector_hash_id=excluded.collector_hash_id" };
        return stmt;
    }

    /**
     * Generate bulk values statement for SQL bulk insert.
     *
     * @return String in the format of (col1, col2, ...)[,...]
     */
    public String genValuesStatement() {
    	
    	//DefaultColumnValues.getDefaultValue("hash");
        StringBuilder sb = new StringBuilder();

        for (int i=0; i < rowMap.size(); i++) {
            if (i > 0)
                sb.append(',');
            sb.append('(');
            sb.append("'" + lookupValue(MsgBusFields.HASH, i) + "'::uuid,");
            sb.append("'" + lookupValue(MsgBusFields.NAME, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.IP_ADDRESS, i)  + "'::inet,");
            sb.append("'" + lookupValue(MsgBusFields.TIMESTAMP, i)  + "'::timestamp,");

            sb.append((((String)lookupValue(MsgBusFields.ACTION, i)).equalsIgnoreCase("term") ? "'down'" : "'up'") + "::opstate,");

            sb.append(  lookupValue(MsgBusFields.TERM_CODE, i) + ",");
            sb.append("'" + lookupValue(MsgBusFields.TERM_REASON, i)  + "',");
            sb.append("'" + lookupValue(MsgBusFields.TERM_DATA, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.INIT_DATA, i)+ "',");
            sb.append("'" + lookupValue(MsgBusFields.DESCRIPTION, i) + "',");
            sb.append("'" + message.getCollector_hash_id() + "'::uuid,");


            if (((String)lookupValue(MsgBusFields.LOCAL_IP, i)).length() > 2)
                sb.append("'" + lookupValue(MsgBusFields.BGP_ID, i) + "'::inet,");
            else
                sb.append("null");
            sb.append(')');
        }

        return sb.toString();
    }

    
    
    

    /**
     * Generate MySQL update statement to update peer status
     *
     * Avoids faulty report of peer status when router gets disconnected
     *
     * @param routerMap         Router tracking map
     *
     * @return Multi statement update is returned, such as update ...; update ...;
     */
    public String genPeerRouterUpdate(Map<String, RouterObject> routerMap) {

        StringBuilder sb = new StringBuilder();

        List<Map<String, Object>> resultMap = new ArrayList<>();
        resultMap.addAll(rowMap);


        for (int i = 0; i < rowMap.size(); i++) {

            // update router object
            RouterObject rObj;

            if (routerMap.containsKey(lookupValue(MsgBusFields.HASH, i))) {
                rObj = routerMap.get(lookupValue(MsgBusFields.HASH, i));

            } else {
                rObj = new RouterObject();
                routerMap.put((String)lookupValue(MsgBusFields.HASH, i), rObj);
            }

            if (((String) lookupValue(MsgBusFields.ACTION, i)).equalsIgnoreCase("first")
                    || ((String) lookupValue(MsgBusFields.ACTION, i)).equalsIgnoreCase("init")) {

                if (sb.length() > 0)
                    sb.append(";");

                if (rObj.connection_count <= 0) {
                    // Upon initial router message, we set the state of all peers to down since we will get peer UP's
                    //    multiple connections can exist, so this is only performed when this is the first connection
                    sb.append("UPDATE bgp_peers SET state = 'down' WHERE router_hash_id = '");
                    sb.append(lookupValue(MsgBusFields.HASH, i) + "'");
                    sb.append(" AND timestamp < '" + rowMap.get(i).get(MsgBusFields.TIMESTAMP.getName()) + "'");
                }

                // bump the connection count
                rObj.connection_count += 1;
            }

            else if (((String) lookupValue(MsgBusFields.ACTION, i)).equalsIgnoreCase("term")) {

                if (rObj.connection_count > 0) {
                    rObj.connection_count -= 1;
                }

                //TODO: Considering updating peers with state = 0 on final term of router (connection_count == 0)
            }
        }

        rowMap = resultMap;

        return sb.toString();
    }

}

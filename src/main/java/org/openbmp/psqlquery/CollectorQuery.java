/*
 * Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 *
 */
package org.openbmp.psqlquery;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.openbmp.RouterObject;
import org.openbmp.api.parsed.message.MsgBusFields;

public class CollectorQuery extends Query{
	
	public CollectorQuery(List<Map<String, Object>> rowMap){
		
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
        String [] stmt = { " INSERT INTO collectors (hash_id,state,admin_id,routers,router_count,timestamp) " +
                                " VALUES ",

                                " ON CONFLICT (hash_id) DO UPDATE SET state=excluded.state,timestamp=excluded.timestamp," +
                                   "routers=excluded.routers,router_count=excluded.router_count" };
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
            sb.append((((String)lookupValue(MsgBusFields.ACTION, i)).equalsIgnoreCase("stopped") ? "'down'" : "'up'") + "::opstate,");
            sb.append("'" + lookupValue(MsgBusFields.ADMIN_ID, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.ROUTERS, i) + "',");
            sb.append(lookupValue(MsgBusFields.ROUTER_COUNT, i) + ",");
            sb.append("'" + lookupValue(MsgBusFields.TIMESTAMP, i) + "'::timestamp");
            sb.append(')');
        }

        return sb.toString();
    }


    /**
     * Generate update statement to update routers
     *
     * @return Multi statement update is returned, such as update ...; update ...;
     */
    public String genRouterCollectorUpdate() {
        Boolean changed = Boolean.FALSE;
        StringBuilder sb = new StringBuilder();
        StringBuilder router_sql_in_list = new StringBuilder();
        router_sql_in_list.append("(");

        for (int i = 0; i < rowMap.size(); i++) {

            String action = (String) lookupValue(MsgBusFields.ACTION, i);

            if (i > 0 && sb.length() > 0)
                sb.append(';');

            if (action.equalsIgnoreCase("started") || action.equalsIgnoreCase("stopped")) {
                sb.append("UPDATE routers SET state = 'down' WHERE collector_hash_id = '");
                sb.append(lookupValue(MsgBusFields.HASH, i) + "'");
            }

            else { // heartbeat or changed
                // nothing
            }
        }

        return sb.toString();
    }


}

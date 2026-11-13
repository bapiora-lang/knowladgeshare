
-- =====================================================================
-- Script       : wait_event_rca.sql
-- Purpose      : Oracle Wait Event Findings, RCA and Recommendations
-- Supports     : Single Instance, RAC, CDB and PDB
-- Output       : FINDINGS / ROOT CAUSE ANALYSIS / RECOMMENDATIONS only
-- Database     : Read-only
--
-- Historical source:
--   GV$ACTIVE_SESSION_HISTORY (in-memory ASH)
--
-- Important:
--   ASH/AWR usage is subject to Oracle Diagnostics Pack licensing.
--   In-memory ASH retention is not guaranteed to cover the full
--   requested historical period.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 500
SET LINESIZE 220
SET TRIMSPOOL ON
SET TAB OFF

ACCEPT p_event CHAR PROMPT 'Enter the wait event name: '
ACCEPT p_mode CHAR DEFAULT S PROMPT 'Enter S or press Enter for Single Instance; enter R for RAC [S]: '
ACCEPT p_minutes NUMBER DEFAULT 120 PROMPT 'Historical window in minutes when event is not active [120]: '

DECLARE
    ------------------------------------------------------------------
    -- User input and environment
    ------------------------------------------------------------------
    l_event          VARCHAR2(200) := TRIM('&&p_event');
    l_mode           VARCHAR2(1)   := UPPER(TRIM('&&p_mode'));
    l_minutes        NUMBER        := &&p_minutes;
    l_instance_count NUMBER;
    l_current_con_id NUMBER;
    l_current_con    VARCHAR2(128);
    l_cdb_flag       VARCHAR2(3);
    l_current_count  NUMBER := 0;
    l_history_count  NUMBER := 0;
    l_event_supported NUMBER := 0;

    ------------------------------------------------------------------
    -- Terminal colors (supported by terminals with ANSI color support)
    ------------------------------------------------------------------
    c_red    CONSTANT VARCHAR2(10) := CHR(27) || '[31m';
    c_yellow CONSTANT VARCHAR2(10) := CHR(27) || '[33m';
    c_green  CONSTANT VARCHAR2(10) := CHR(27) || '[32m';
    c_cyan   CONSTANT VARCHAR2(10) := CHR(27) || '[36m';
    c_white  CONSTANT VARCHAR2(10) := CHR(27) || '[37m';
    c_reset  CONSTANT VARCHAR2(10) := CHR(27) || '[0m';

    ------------------------------------------------------------------
    -- Print helper
    ------------------------------------------------------------------
    PROCEDURE line_out(p_text VARCHAR2, p_color VARCHAR2 DEFAULT c_white) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_color || p_text || c_reset);
    END;

    ------------------------------------------------------------------
    -- Event-specific root cause analysis
    ------------------------------------------------------------------
    FUNCTION event_rca(p_event VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        CASE p_event
            WHEN 'db file sequential read' THEN
                RETURN 'Single-block physical reads are taking place. Possible causes include inefficient index access, high random I/O latency, or excessive index/table lookups.';
            WHEN 'db file scattered read' THEN
                RETURN 'Multi-block physical reads are taking place. Possible causes include full table scans, large range scans, or insufficiently selective access paths.';
            WHEN 'direct path read' THEN
                RETURN 'Direct path reads are occurring. Investigate large scans, parallel execution, temporary operations, and storage read latency.';
            WHEN 'log file parallel write' THEN
                RETURN 'LGWR is waiting for redo writes to complete. Investigate redo storage latency, I/O throughput, and redo log device contention.';
            WHEN 'db file parallel write' THEN
                RETURN 'DBWR is waiting for database block writes. Investigate datafile storage latency, write throughput, and checkpoint workload.';
            WHEN 'control file sequential read' THEN
                RETURN 'Control file read operations are waiting. Investigate control file storage latency, control file multiplexing, and excessive control file activity.';
            WHEN 'latch: cache buffers chains' THEN
                RETURN 'Sessions are competing for cache buffers chains latches. Possible causes include hot blocks, heavily accessed indexes, or buffer chain contention.';
            WHEN 'cursor: pin S wait on X' THEN
                RETURN 'A session is waiting for an exclusive cursor pin. Investigate concurrent cursor invalidation, hard parsing, DDL, and shared SQL cursor contention.';
            WHEN 'buffer busy waits' THEN
                RETURN 'Sessions are competing for buffers that are currently busy. Investigate hot blocks, segment contention, and concurrent block access.';
            WHEN 'library cache lock' THEN
                RETURN 'Library cache objects are involved in lock contention. Investigate DDL, object invalidation, compilation, and concurrent access to shared objects.';
            WHEN 'enq: TX - row lock contention' THEN
                RETURN 'A transaction is waiting for another transaction to release a row lock. Investigate the blocking transaction and application transaction duration.';
            WHEN 'enq: TM - contention' THEN
                RETURN 'A table-level enqueue is contended. Investigate unindexed foreign keys, concurrent DML, and conflicting table operations.';
            WHEN 'log file sync' THEN
                RETURN 'A foreground session is waiting for a commit-related redo flush. Investigate LGWR latency, redo storage performance, and excessive commit frequency.';
            WHEN 'gc cr block 2-way' THEN
                RETURN 'A RAC instance is requesting a consistent-read block from another instance. Investigate interconnect latency, block access patterns, and cross-instance workload.';
            WHEN 'gc current block busy' THEN
                RETURN 'A RAC current block request is delayed. Investigate hot blocks, concurrent modifications, and inter-instance block transfer delays.';
            WHEN 'gc buffer busy acquire' THEN
                RETURN 'A session is waiting for a RAC buffer transfer or access to a busy global cache buffer. Investigate hot blocks and global cache contention.';
            WHEN 'SQL*Net message from dblink' THEN
                RETURN 'The local session is waiting for a response from a remote database over a database link. Investigate remote database response time and network latency.';
            WHEN 'SQL*Net more data to client' THEN
                RETURN 'Oracle is sending additional data to the client. Investigate result-set size, client fetch rate, network throughput, and application processing.';
            WHEN 'log file switch (checkpoint incomplete)' THEN
                RETURN 'A redo log switch is delayed because the checkpoint has not completed. Investigate DBWR throughput, datafile I/O latency, and checkpoint workload.';
            WHEN 'enq: TX - allocate ITL entry' THEN
                RETURN 'A transaction is waiting for an ITL entry in a data block. Investigate concurrent DML on the same blocks and available ITL capacity.';
            WHEN 'Backup: MML write backup piece' THEN
                RETURN 'The backup process is waiting for the media management layer to write a backup piece. Investigate backup software, media manager, and backup destination throughput.';
            WHEN 'index (re)build online start' THEN
                RETURN 'An online index rebuild operation may be waiting during its start phase. Investigate concurrent DML, index maintenance activity, and related DDL operations.';
            WHEN 'resmgr:cpu quantum' THEN
                RETURN 'The Resource Manager is scheduling CPU allocation. Investigate resource plans, consumer group limits, CPU utilization, and competing workloads.';
            WHEN 'Streams AQ: waiting for messages in the queue' THEN
                RETURN 'A session is waiting for queue messages. Investigate queue message arrival, propagation, subscribers, and AQ processing configuration.';
            WHEN 'DFS lock handle' THEN
                RETURN 'A distributed file system lock request is waiting. Investigate distributed lock activity and related cluster or file-system operations.';
            WHEN 'ges remote message' THEN
                RETURN 'A Global Enqueue Service remote message is involved. Investigate RAC interconnect communication and global enqueue activity.';
            WHEN 'PX Deq: Execution Msg' THEN
                RETURN 'A parallel execution process is waiting for an execution message. Investigate parallel execution skew, producer/consumer imbalance, and PX workload.';
            WHEN 'SQL*Net message from client' THEN
                RETURN 'The session is waiting for the client to send its next message. This is normally an idle wait; investigate only if application response or connection behaviour is abnormal.';
            WHEN 'rdbms ipc message' THEN
                RETURN 'A background process is waiting for an inter-process communication message. This is normally an idle background wait unless accompanied by other evidence.';
            WHEN 'pmon timer' THEN
                RETURN 'PMON is waiting for its next scheduled activity. This is normally an idle background wait.';
            ELSE
                RETURN 'No event-specific RCA mapping is available for this event in the script.';
        END CASE;
    END;

    ------------------------------------------------------------------
    -- Event-specific recommendations
    ------------------------------------------------------------------
    FUNCTION event_recommendation(p_event VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        CASE p_event
            WHEN 'db file sequential read' THEN
                RETURN 'Review SQL execution plans, index access patterns, physical read volume, and storage read latency. Tune only after identifying the SQL and access path responsible.';
            WHEN 'db file scattered read' THEN
                RETURN 'Identify SQL performing large scans. Review execution plans, predicates, table statistics, and whether full scans are appropriate.';
            WHEN 'direct path read' THEN
                RETURN 'Identify the SQL and segment generating direct reads. Review parallelism, scan volume, temporary usage, and storage throughput.';
            WHEN 'log file parallel write' THEN
                RETURN 'Review redo log device latency and throughput, LGWR performance, and redo log placement. Check storage health before considering configuration changes.';
            WHEN 'db file parallel write' THEN
                RETURN 'Review DBWR activity, datafile write latency, checkpoint workload, and storage throughput.';
            WHEN 'control file sequential read' THEN
                RETURN 'Review control file I/O latency and control file activity. Validate the underlying storage path.';
            WHEN 'latch: cache buffers chains' THEN
                RETURN 'Identify hot blocks and SQL accessing them. Review segment-level contention and execution frequency before considering SQL or application changes.';
            WHEN 'cursor: pin S wait on X' THEN
                RETURN 'Identify the SQL_ID and sessions involved. Review invalidations, parsing activity, DDL, and cursor sharing behaviour.';
            WHEN 'buffer busy waits' THEN
                RETURN 'Identify the affected object and block. Review concurrent access, segment configuration, and application DML patterns.';
            WHEN 'library cache lock' THEN
                RETURN 'Identify the object and blocking session. Review DDL, compilation, invalidation, and long-running transactions.';
            WHEN 'enq: TX - row lock contention' THEN
                RETURN 'Identify the blocker and blocked sessions. Coordinate with the application owner to complete or safely resolve the blocking transaction.';
            WHEN 'enq: TM - contention' THEN
                RETURN 'Identify the object and blocking SQL. Check foreign-key indexes and concurrent DML or DDL operations.';
            WHEN 'log file sync' THEN
                RETURN 'Correlate commit response time with log file parallel write latency. Review commit frequency, LGWR performance, and redo storage latency.';
            WHEN 'gc cr block 2-way' THEN
                RETURN 'Identify SQL and objects involved in cross-instance block requests. Review service placement, hot blocks, and RAC interconnect performance.';
            WHEN 'gc current block busy' THEN
                RETURN 'Identify hot blocks and modifying instances. Review block-level contention, workload distribution, and interconnect health.';
            WHEN 'gc buffer busy acquire' THEN
                RETURN 'Identify affected objects and SQL. Review hot-block access and cross-instance workload distribution.';
            WHEN 'SQL*Net message from dblink' THEN
                RETURN 'Check remote database availability, remote SQL performance, database link network path, and response time.';
            WHEN 'SQL*Net more data to client' THEN
                RETURN 'Review result-set volume, application fetch behaviour, network throughput, and unnecessary data transfer.';
            WHEN 'log file switch (checkpoint incomplete)' THEN
                RETURN 'Review checkpoint completion, DBWR throughput, datafile I/O latency, and redo log switch frequency.';
            WHEN 'enq: TX - allocate ITL entry' THEN
                RETURN 'Identify the affected object and concurrent DML pattern. Review INITRANS, block space utilisation, and transaction concurrency before changing object settings.';
            WHEN 'Backup: MML write backup piece' THEN
                RETURN 'Check media manager logs, backup destination throughput, tape or storage availability, and backup software health.';
            WHEN 'index (re)build online start' THEN
                RETURN 'Review the index rebuild operation, concurrent DML, related locks, and DDL execution status.';
            WHEN 'resmgr:cpu quantum' THEN
                RETURN 'Review the active Resource Manager plan, consumer group directives, CPU utilisation, and SQL workload distribution.';
            WHEN 'Streams AQ: waiting for messages in the queue' THEN
                RETURN 'Check queue depth, message arrival rate, subscriber health, propagation status, and AQ processing.';
            WHEN 'DFS lock handle' THEN
                RETURN 'Review distributed lock activity and relevant cluster or file-system diagnostics.';
            WHEN 'ges remote message' THEN
                RETURN 'Review RAC interconnect latency, global enqueue activity, and cluster communication health.';
            WHEN 'PX Deq: Execution Msg' THEN
                RETURN 'Review the parallel SQL execution plan, PX server distribution, data skew, and producer/consumer workload balance.';
            WHEN 'SQL*Net message from client' THEN
                RETURN 'Normally no action is required. If application delays are reported, review client processing and connection behaviour.';
            WHEN 'rdbms ipc message' THEN
                RETURN 'Normally no action is required. Investigate only when supported by abnormal background-process or database symptoms.';
            WHEN 'pmon timer' THEN
                RETURN 'Normally no action is required. Investigate only when other evidence indicates a background-process problem.';
            ELSE
                RETURN 'Collect event-specific session, SQL, object, and blocking evidence before taking corrective action.';
        END CASE;
    END;

BEGIN
    ------------------------------------------------------------------
    -- Validate user input
    ------------------------------------------------------------------
    IF l_event IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Wait event name cannot be empty.');
    END IF;

    IF l_mode NOT IN ('S', 'R') THEN
        RAISE_APPLICATION_ERROR(-20002, 'Invalid environment selection. Enter S or R.');
    END IF;

    IF l_minutes < 1 OR l_minutes > 10080 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Historical window must be between 1 and 10080 minutes.');
    END IF;

    SELECT COUNT(*)
    INTO l_event_supported
    FROM (
        SELECT 'db file sequential read' event_name FROM dual UNION ALL
        SELECT 'db file scattered read' FROM dual UNION ALL
        SELECT 'direct path read' FROM dual UNION ALL
        SELECT 'log file parallel write' FROM dual UNION ALL
        SELECT 'db file parallel write' FROM dual UNION ALL
        SELECT 'control file sequential read' FROM dual UNION ALL
        SELECT 'latch: cache buffers chains' FROM dual UNION ALL
        SELECT 'cursor: pin S wait on X' FROM dual UNION ALL
        SELECT 'buffer busy waits' FROM dual UNION ALL
        SELECT 'library cache lock' FROM dual UNION ALL
        SELECT 'enq: TX - row lock contention' FROM dual UNION ALL
        SELECT 'enq: TM - contention' FROM dual UNION ALL
        SELECT 'log file sync' FROM dual UNION ALL
        SELECT 'gc cr block 2-way' FROM dual UNION ALL
        SELECT 'gc current block busy' FROM dual UNION ALL
        SELECT 'gc buffer busy acquire' FROM dual UNION ALL
        SELECT 'SQL*Net message from dblink' FROM dual UNION ALL
        SELECT 'SQL*Net more data to client' FROM dual UNION ALL
        SELECT 'log file switch (checkpoint incomplete)' FROM dual UNION ALL
        SELECT 'enq: TX - allocate ITL entry' FROM dual UNION ALL
        SELECT 'Backup: MML write backup piece' FROM dual UNION ALL
        SELECT 'index (re)build online start' FROM dual UNION ALL
        SELECT 'resmgr:cpu quantum' FROM dual UNION ALL
        SELECT 'Streams AQ: waiting for messages in the queue' FROM dual UNION ALL
        SELECT 'DFS lock handle' FROM dual UNION ALL
        SELECT 'ges remote message' FROM dual UNION ALL
        SELECT 'PX Deq: Execution Msg' FROM dual UNION ALL
        SELECT 'SQL*Net message from client' FROM dual UNION ALL
        SELECT 'rdbms ipc message' FROM dual UNION ALL
        SELECT 'pmon timer' FROM dual
    )
    WHERE LOWER(event_name) = LOWER(l_event);

    IF l_event_supported = 0 THEN
        RAISE_APPLICATION_ERROR(-20004, 'Event is not in the supported event list.');
    END IF;

    -- Normalise case to the script's event names.
    l_event := LOWER(l_event);

    ------------------------------------------------------------------
    -- Detect database topology and current container
    ------------------------------------------------------------------
    SELECT COUNT(*) INTO l_instance_count FROM gv$instance;

    SELECT TO_NUMBER(SYS_CONTEXT('USERENV', 'CON_ID')),
           SYS_CONTEXT('USERENV', 'CON_NAME')
    INTO l_current_con_id, l_current_con
    FROM dual;

    SELECT cdb INTO l_cdb_flag FROM v$database;

    IF l_mode = 'S' AND l_instance_count > 1 THEN
        RAISE_APPLICATION_ERROR(-20005,
            'RAC database detected. Select R for RAC.');
    ELSIF l_mode = 'R' AND l_instance_count = 1 THEN
        RAISE_APPLICATION_ERROR(-20006,
            'Single Instance database detected. Select S for Single Instance.');
    END IF;

    ------------------------------------------------------------------
    -- CURRENT EVENT CHECK
    -- If active, do not execute the historical ASH query.
    ------------------------------------------------------------------
    FOR r IN (
        SELECT s.inst_id,
               s.sid,
               s.serial#,
               s.username,
               s.status,
               s.event,
               s.wait_class,
               s.state,
               s.seconds_in_wait,
               s.sql_id,
               s.sql_child_number,
               s.blocking_instance,
               s.blocking_session,
               s.con_id,
               NVL(c.name,
                   CASE
                       WHEN s.con_id = l_current_con_id THEN l_current_con
                       WHEN s.con_id = 0 THEN 'NON-CDB'
                       ELSE 'CON_ID=' || TO_CHAR(s.con_id)
                   END) AS container_name
        FROM gv$session s
        LEFT JOIN v$containers c
               ON c.con_id = s.con_id
        WHERE LOWER(s.event) = l_event
          AND s.state = 'WAITING'
          AND (l_current_con_id IN (0, 1) OR s.con_id = l_current_con_id)
        ORDER BY s.seconds_in_wait DESC
    ) LOOP
        l_current_count := l_current_count + 1;

        IF l_current_count = 1 THEN
            line_out('FINDINGS', c_cyan);
            line_out('Selected event       : ' || l_event);
            line_out('Database mode        : ' ||
                     CASE WHEN l_mode = 'R' THEN 'RAC' ELSE 'Single Instance' END);
            line_out('Database type        : ' || l_cdb_flag);
            line_out('Connected container  : ' || l_current_con);
            line_out('Analysis status      : CURRENT EVENT DETECTED', c_red);
            line_out('Current waiting sessions:', c_yellow);
        END IF;

        line_out('------------------------------------------------------------');
        line_out('Instance ID          : ' || r.inst_id);
        line_out('SID / SERIAL#        : ' || r.sid || ' / ' || r.serial#);
        line_out('Container / PDB      : ' || r.container_name);
        line_out('CON_ID               : ' || r.con_id);
        line_out('Username             : ' || NVL(r.username, 'BACKGROUND'));
        line_out('Session status       : ' || r.status);
        line_out('Wait class           : ' || r.wait_class);
        line_out('Wait duration (sec)  : ' || r.seconds_in_wait);
        line_out('SQL_ID               : ' || NVL(r.sql_id, 'N/A'));
        line_out('Blocking instance    : ' || NVL(TO_CHAR(r.blocking_instance), 'N/A'));
        line_out('Blocking session     : ' || NVL(TO_CHAR(r.blocking_session), 'N/A'));
    END LOOP;

    ------------------------------------------------------------------
    -- CURRENT EVENT REPORT
    ------------------------------------------------------------------
    IF l_current_count > 0 THEN
        line_out(' ');
        line_out('ROOT CAUSE ANALYSIS', c_cyan);
        line_out(event_rca(l_event), c_yellow);

        line_out(' ');
        line_out('RECOMMENDATIONS', c_cyan);
        line_out(event_recommendation(l_event), c_green);

    ELSE
        ----------------------------------------------------------------
        -- No current occurrence: historical ASH analysis only
        ----------------------------------------------------------------
        SELECT COUNT(*)
        INTO l_history_count
        FROM gv$active_session_history h
        WHERE LOWER(h.event) = l_event
          AND h.session_state = 'WAITING'
          AND h.sample_time >=
              SYSTIMESTAMP - NUMTODSINTERVAL(l_minutes, 'MINUTE')
          AND (l_current_con_id IN (0, 1) OR h.con_id = l_current_con_id);

        line_out('FINDINGS', c_cyan);
        line_out('Selected event       : ' || l_event);
        line_out('Database mode        : ' ||
                 CASE WHEN l_mode = 'R' THEN 'RAC' ELSE 'Single Instance' END);
        line_out('Database type        : ' || l_cdb_flag);
        line_out('Connected container  : ' || l_current_con);
        line_out('Current event status : NOT CURRENTLY ACTIVE', c_green);
        line_out('Historical window    : Last ' || l_minutes || ' minutes');

        IF l_history_count = 0 THEN
            line_out('Historical ASH samples: No matching samples found.', c_yellow);
        ELSE
            line_out('Historical ASH samples: ' || l_history_count, c_red);
            line_out('Historical event details:', c_yellow);

            FOR h IN (
                SELECT *
                FROM (
                    SELECT h.inst_id,
                           h.con_id,
                           NVL(c.name,
                               CASE
                                   WHEN h.con_id = l_current_con_id THEN l_current_con
                                   WHEN h.con_id = 0 THEN 'NON-CDB'
                                   ELSE 'CON_ID=' || TO_CHAR(h.con_id)
                               END) AS container_name,
                           h.sql_id,
                           h.session_id,
                           h.session_serial#,
                           h.blocking_inst_id,
                           h.blocking_session,
                           h.current_obj#,
                           COUNT(*) AS sample_count,
                           MIN(h.sample_time) AS first_seen,
                           MAX(h.sample_time) AS last_seen
                    FROM gv$active_session_history h
                    LEFT JOIN v$containers c
                           ON c.con_id = h.con_id
                    WHERE LOWER(h.event) = l_event
                      AND h.session_state = 'WAITING'
                      AND h.sample_time >=
                          SYSTIMESTAMP - NUMTODSINTERVAL(l_minutes, 'MINUTE')
                      AND (l_current_con_id IN (0, 1) OR h.con_id = l_current_con_id)
                    GROUP BY h.inst_id,
                             h.con_id,
                             c.name,
                             h.sql_id,
                             h.session_id,
                             h.session_serial#,
                             h.blocking_inst_id,
                             h.blocking_session,
                             h.current_obj#
                    ORDER BY COUNT(*) DESC
                )
                WHERE ROWNUM <= 20
            ) LOOP
                line_out('------------------------------------------------------------');
                line_out('Instance ID          : ' || h.inst_id);
                line_out('Container / PDB      : ' || h.container_name);
                line_out('CON_ID               : ' || h.con_id);
                line_out('SID / SERIAL#        : ' ||
                         h.session_id || ' / ' || h.session_serial#);
                line_out('SQL_ID               : ' || NVL(h.sql_id, 'N/A'));
                line_out('Blocking instance    : ' ||
                         NVL(TO_CHAR(h.blocking_inst_id), 'N/A'));
                line_out('Blocking session     : ' ||
                         NVL(TO_CHAR(h.blocking_session), 'N/A'));
                line_out('Current object ID    : ' ||
                         NVL(TO_CHAR(h.current_obj#), 'N/A'));
                line_out('ASH sample count     : ' || h.sample_count);
                line_out('First observed       : ' ||
                         TO_CHAR(h.first_seen, 'YYYY-MM-DD HH24:MI:SS'));
                line_out('Last observed        : ' ||
                         TO_CHAR(h.last_seen, 'YYYY-MM-DD HH24:MI:SS'));
            END LOOP;

            line_out(' ');
            line_out('ROOT CAUSE ANALYSIS', c_cyan);
            line_out(event_rca(l_event), c_yellow);

            line_out(' ');
            line_out('RECOMMENDATIONS', c_cyan);
            line_out(event_recommendation(l_event), c_green);
        END IF;

        IF l_history_count = 0 THEN
            line_out(' ');
            line_out('ROOT CAUSE ANALYSIS', c_cyan);
            line_out('No matching historical ASH evidence was found in the requested window.', c_yellow);

            line_out(' ');
            line_out('RECOMMENDATIONS', c_cyan);
            line_out('No event-specific corrective action is recommended without supporting evidence.', c_green);
        END IF;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(c_red || 'Diagnostic execution error: ' ||
                             SQLERRM || c_reset);
        RAISE;
END;
/

UNDEFINE p_event
UNDEFINE p_mode
UNDEFINE p_minutes

SET FEEDBACK ON
SET VERIFY ON

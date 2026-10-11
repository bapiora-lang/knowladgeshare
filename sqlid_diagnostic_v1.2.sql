/*==============================================================================
  SQL_ID / SID DIAGNOSTIC SCRIPT  -  version 2   (Oracle 19c; 12c+ compatible)
  organised by :- Biswajit Datta
  ------------------------------------------------------------------------------
  FIX (section 1.4): ORA-00904 "PGA_ALLOCATED" - V$SQL_MONITOR has no such column.
    Query rebuilt on valid V$SQL_MONITOR columns; rows processed / work-area memory
    are derived from V$SQL_PLAN_MONITOR (column-checked per release); pack,
    privilege and no-data cases now give an informational message.
  ------------------------------------------------------------------------------
  WHAT CHANGED IN V1.2.8  (section 1.5 and 1.6)
    - 1.5 (SQL Monitor report) gets two bind subsections: 1.5.1 the bind values actually used by
      the monitored executions (V$SQL_MONITOR.BINDS_XML) and 1.5.2 the binds captured by the
      optimizer (V$SQL_BIND_CAPTURE: child, position, name, data type, captured?, time, value).
    - 1.6 now also prints the PEEKED BINDS the plan was built with (DBMS_XPLAN +PEEKED_BINDS).
    - New switch DEFINE show_binds (default Y). Bind values are application data; set N to
      leave them out, especially before e-mailing the report. Read-only: SELECTs only.
    - Extra read access (optional; a missing one only skips that subsection): V$SQL_MONITOR
      (BINDS_XML, Tuning Pack) and V$SQL_BIND_CAPTURE.

  WHAT CHANGED IN V1.2.7  (sections 1.6 and 1.7 only)
    - The plan from the cursor cache (1.6) and from AWR (1.7) is now shown in three
      collapsible blocks: the plan table, the PLAN OUTLINE (the "Outline Data" hints
      that reproduce the plan, usable for a SQL plan baseline / hint comparison) and the
      predicate information / notes. 1.7 now requests 'ALL +OUTLINE'. Read-only: still
      a SELECT on DBMS_XPLAN. New helper procedure PUT_XPLAN.

  WHAT CHANGED IN V2
    - The script now writes the HTML report DIRECTLY (sqlid_diag_<id>_<ts>.html).
      There is no raw SQL*Plus spool any more, so the "Complete Raw Output"
      section no longer exists and sqlid_report.py is no longer needed.
      Only e-mail delivery remains (sqlid_mail.py, optional).
    - The whole report is ONE PL/SQL block: DECLARE ... BEGIN ... EXCEPTION ...
      END; followed by "/". SQL*Plus therefore never sees individual PL/SQL
      statements (fixes SP2-0734 and PLS-00201 for C_WAITS / V_FOUND).
    - All queries on V$ / DBA_HIST views are dynamic SQL with bind variables, so
      a missing privilege or licence affects only that sub-section (a message is
      shown in the report) and never breaks compilation of the whole block.
    - Section 2.2 : V$SQLSTATS has NO column FIRST_LOAD_TIME (ORA-00904).
      Load time now comes from V$SQLAREA.FIRST_LOAD_TIME (one row per SQL_ID),
      joined to V$SQLSTATS; LAST_ACTIVE_TIME comes from V$SQLSTATS.
    - Section 4 : current waits, blocking chain, wait guidance and ASH profile
      redesigned as readable tables with decoded values.
    - Section 5 : NEW Plan Stability Check (immediately before section 6).
    - Section 6 : Findings and Recommendations (existing checks, with the
      false-negative cases fixed - see notes in the section).

  WHAT CHANGED IN V1.2  (section 5.4 only; everything else is unchanged)
    - Related Table Statistics / Related Index Statistics: every table and index of
      the analysed plan (V$SQL_PLAN, AWR plan as fallback), duplicates removed, with
      LAST_ANALYZED, Oracle's STALE_STATS flag (STALE / NOT STALE / UNKNOWN / MISSING),
      row/block/sample figures, index validity (UNUSABLE shown separately) and
      partition-level counts.
    - Related Table and Index Fragmentation Analysis: segment size, blocks, extents and
      a statistics-based indicator. No VALIDATE STRUCTURE / segment analysis is run;
      HIGH is never assigned automatically. Thresholds: DEFINE frag_* below.
    - Extra read access used by 5.4 (direct grants): DBA_TAB_STATISTICS, DBA_IND_STATISTICS,
      DBA_TABLES, DBA_INDEXES, DBA_IND_PARTITIONS, DBA_IND_SUBPARTITIONS, DBA_SEGMENTS,
      DBA_OBJECTS and DBA_TAB_MODIFICATIONS (last DDL / DML table).
      Without DBA_* the ALL_* views are used (only objects visible to the user);
      without DBA_SEGMENTS fragmentation is shown as NOT ASSESSED.

  WHAT CHANGED IN V1.2  (section 6)
    - Section 6 no longer prints a fixed list of generic checks. It first shows the
      measured workload of the analysed plan (6.1: V$SQLSTATS, AWR as fallback), then
      lists findings (6.2) that each carry the actual evidence of this SQL_ID: object
      names, numbers, timestamps, predicates, plan step ids and plan hash values, with
      a recommended action and how to confirm the result. Findings are sorted High /
      Review / Info and a "Main finding" is named. A finding appears only when its
      evidence crosses a stated threshold; if nothing does, the report says so.
    - Findings come from: time profile (I/O, CPU, locks, concurrency, cluster), buffer
      gets per row, execution frequency, invalidations, fetch size, plan instability
      (best vs worst plan, baselines), optimizer parameter changes in 7 days, cartesian
      joins, the plan step using most buffer gets, cardinality misestimates, work-area
      spills, top ASH wait, blocked sessions now, and per-table / per-index data of
      5.4 (stale or missing statistics, DML volume, recent DDL, TRUNCATE, unusable
      index, full scans with their predicate and candidate indexes, clustering factor).
    - Extra read access for these findings (all optional; a missing one only skips its
      finding): V$SQLSTATS, V$SQL, V$SQL_WORKAREA, V$SQL_PLAN_STATISTICS_ALL,
      V$PARAMETER, DBA_HIST_SNAPSHOT, DBA_HIST_ACTIVE_SESS_HISTORY, DBA_IND_COLUMNS
      (or ALL_IND_COLUMNS).
    - Nothing is executed against user objects: the recommended statements are text in
      the report only.

  READ-ONLY GUARANTEES  (added after a security review)
    - The session starts with SET TRANSACTION READ ONLY, so the database itself refuses any
      data change from this script (ORA-01456).
    - Every dynamic statement is a SELECT (including DBMS_XPLAN and DBMS_SQLTUNE.REPORT_SQL_MONITOR,
      which are called from a SELECT). No INSERT/UPDATE/DELETE/MERGE/DDL/COMMIT/DBMS_STATS call
      is executed; DBMS_STATS / DBMS_SPM / ALTER INDEX text in section 6 is printed, never run.
    - The report refuses to run under an account holding privileges that can modify the database
      (SYSDBA, ALTER SYSTEM, *ANY TABLE write rights, GRANT ANY ..., etc.) unless
      DEFINE allow_privileged = Y. Use a dedicated account with SELECT grants only.
    - E-mail (an operating-system call, not a database operation) is OFF unless send_mail = Y.
    - Not covered: the SQL_ID/SID you type is substituted into SQL*Plus text (SQL*Plus
      limitation); it can only run with the privileges of the read-only account.

  RUN AS A SCRIPT FILE (do not paste line by line into an interactive prompt):
      sqlplus user/pass@db
      SQL> @sqlid_diagnostic_v2.sql
  If the file was edited on Windows, convert it first:  dos2unix sqlid_diagnostic_v2.sql

  PRIVILEGES REQUIRED (direct grants, not via role, because of PL/SQL):
    SELECT on V$SESSION, V$SQL, V$SQLAREA, V$SQLSTATS, V$SQL_MONITOR, V$SQL_PLAN,
    V$SQL_PLAN_STATISTICS_ALL, V$SQL_SHARED_CURSOR, V$SQL_WORKAREA, V$INSTANCE,
    V$DATABASE, DBA_TAB_STATISTICS, DBA_HIST_SQLSTAT, DBA_HIST_SQLTEXT,
    DBA_HIST_SQL_PLAN, DBA_HIST_SNAPSHOT, DBA_HIST_ACTIVE_SESS_HISTORY,
    DBA_HIST_PARAMETER;  EXECUTE on DBMS_XPLAN and DBMS_SQLTUNE.
    (AWR / ASH / DBMS_SQLTUNE need the Diagnostics + Tuning Pack licence.)
==============================================================================*/

SET DEFINE ON
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET VERIFY OFF
SET ECHO OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 1000
SET LINESIZE 32767
SET LONG 1000000
SET LONGCHUNKSIZE 1000000
SET TRIMSPOOL ON
SET TAB OFF
SET SQLBLANKLINES ON
SET TIMING OFF
CLEAR SCREEN

-- READ-ONLY SAFEGUARDS
--   allow_privileged : N (default) = the report stops if this account holds privileges that
--                      could change data, objects or the instance (DBA-type rights).
--                      Y = continue anyway (a warning is shown). Best practice: run with a
--                      dedicated account that has SELECT grants only.
--   send_mail        : N (default) = the report is only written to a file. Y = after the report
--                      has been written, call the optional e-mail helper (an operating-system
--                      command, not a database operation).
--   show_binds       : Y (default) = section 1.5 lists the bind variable values of the monitored
--                      executions and the captured binds, and 1.6 adds the peeked binds. Bind values
--                      are application data (they can hold names, ids, amounts). Set N to leave them
--                      out, in particular when the report is e-mailed or shared outside the DBA team.
DEFINE allow_privileged = Y
DEFINE send_mail        = Y
DEFINE show_binds       = Y

DEFINE rpt_python = 'python3'
DEFINE rpt_helper = 'sqlid_mail.py'

-- Review thresholds for the fragmentation indicators in section 5.4 (estimates, not universal rules).
--   frag_min_mb  : segments smaller than this (MB) are not flagged
--   frag_density : table - estimated block density (%) below which MODERATE / REVIEW is shown
--   frag_ratio   : index - allocated blocks / leaf blocks above which MODERATE / REVIEW is shown
DEFINE frag_min_mb  = 100
DEFINE frag_density = 50
DEFINE frag_ratio   = 2

-- Everything this script does in the database is a query. The read-only transaction makes the
-- database itself refuse any data change in this session (ORA-01456).
SET TRANSACTION READ ONLY;

COLUMN rpt_ts   NEW_VALUE v_rpt_ts   NOPRINT
COLUMN rpt_time NEW_VALUE v_rpt_time NOPRINT
COLUMN rpt_db   NEW_VALUE v_rpt_db   NOPRINT
SET TERMOUT OFF
SELECT TO_CHAR(SYSDATE,'YYYYMMDD_HH24MISS') AS rpt_ts, TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS rpt_time, SYS_CONTEXT('USERENV','DB_NAME') AS rpt_db FROM dual;
SET TERMOUT ON

ACCEPT input_val PROMPT 'Enter SQL_ID or SID (session id) to diagnose: '

-- Resolve the input into a SQL_ID. Numeric input = SID (active SQL_ID, or the
-- previous one if the session is idle). 13 alphanumeric characters = SQL_ID.
COLUMN resolved_sql_id NEW_VALUE v_sql_id NOPRINT
COLUMN resolved_sid    NEW_VALUE v_sid    NOPRINT
SET TERMOUT OFF
SELECT NVL(x.sql_id,'UNKNOWN') AS resolved_sql_id, NVL(TO_CHAR(x.sid),'N/A') AS resolved_sid FROM (SELECT CASE WHEN REGEXP_LIKE(TRIM('&&input_val'),'^[0-9]+$') THEN (SELECT NVL(s.sql_id, s.prev_sql_id) FROM v$session s WHERE s.sid = TO_NUMBER(TRIM('&&input_val'))) WHEN REGEXP_LIKE(TRIM('&&input_val'),'^[0-9A-Za-z]{13}$') THEN LOWER(TRIM('&&input_val')) ELSE 'INVALID' END AS sql_id, CASE WHEN REGEXP_LIKE(TRIM('&&input_val'),'^[0-9]+$') THEN TO_NUMBER(TRIM('&&input_val')) WHEN REGEXP_LIKE(TRIM('&&input_val'),'^[0-9A-Za-z]{13}$') THEN (SELECT MAX(s.sid) FROM v$session s WHERE s.sql_id = LOWER(TRIM('&&input_val')) OR s.prev_sql_id = LOWER(TRIM('&&input_val'))) END AS sid FROM dual) x;

COLUMN rpt_file NEW_VALUE v_rpt_file NOPRINT
SELECT 'sqlid_diag_' || '&&v_sql_id' || '_' || '&&v_rpt_ts' || '.html' AS rpt_file FROM dual;
SET TERMOUT ON

-- Hand the values to the PL/SQL block through bind variables, so that no
-- substitution variable is needed inside the block.
VARIABLE b_sql_id VARCHAR2(30)
VARIABLE b_sid    VARCHAR2(30)
VARIABLE b_input  VARCHAR2(100)
EXEC :b_sql_id := '&&v_sql_id'
EXEC :b_sid    := '&&v_sid'
EXEC :b_input  := TRIM('&&input_val')
-- Privilege probe: a report must not run under an account able to modify the database.
VARIABLE b_priv        VARCHAR2(2000)
VARIABLE b_allow_priv  VARCHAR2(1)
EXEC :b_allow_priv := UPPER(SUBSTR('&&allow_privileged', 1, 1))
DECLARE
    l_list VARCHAR2(2000);
BEGIN
    FOR r IN (SELECT privilege FROM session_privs
              WHERE  privilege IN ('SYSDBA', 'SYSOPER', 'ALTER SYSTEM', 'ALTER DATABASE', 'CREATE ANY TABLE', 'ALTER ANY TABLE', 'DROP ANY TABLE',
                                   'INSERT ANY TABLE', 'UPDATE ANY TABLE', 'DELETE ANY TABLE', 'CREATE ANY INDEX', 'ALTER ANY INDEX', 'DROP ANY INDEX',
                                   'CREATE ANY PROCEDURE', 'EXECUTE ANY PROCEDURE', 'ANALYZE ANY', 'GRANT ANY PRIVILEGE', 'GRANT ANY ROLE',
                                   'ALTER USER', 'DROP USER')
              ORDER BY privilege) LOOP
        l_list := SUBSTR(l_list || CASE WHEN l_list IS NOT NULL THEN ', ' END || r.privilege, 1, 1900);
    END LOOP;
    :b_priv := l_list;
EXCEPTION
    WHEN OTHERS THEN
        :b_priv := 'the privilege check itself failed (' || SUBSTR(SQLERRM, 1, 150) || ')';
END;
/
VARIABLE b_frag_min_mb   NUMBER
VARIABLE b_frag_density  NUMBER
VARIABLE b_frag_ratio    NUMBER
EXEC :b_frag_min_mb  := &&frag_min_mb
EXEC :b_frag_density := &&frag_density
EXEC :b_frag_ratio   := &&frag_ratio
VARIABLE b_show_binds    VARCHAR2(1)
EXEC :b_show_binds   := UPPER(SUBSTR('&&show_binds', 1, 1))

PROMPT Generating HTML report for SQL_ID &&v_sql_id ...

SET HEADING OFF
SET PAGESIZE 0
SET TERMOUT OFF
SPOOL &&v_rpt_file
-- From here on the HTML text contains literal ampersand characters (HTML entities)
SET DEFINE OFF

DECLARE
    ---------------------------------------------------------------------------
    -- TYPES
    ---------------------------------------------------------------------------
    TYPE t_rc IS REF CURSOR;
    --
    TYPE t_live IS RECORD (sid NUMBER, serial NUMBER, username VARCHAR2(200), status VARCHAR2(30),
                           rel VARCHAR2(10), exec_start DATE, call_et NUMBER, event VARCHAR2(200),
                           wait_class VARCHAR2(100), state VARCHAR2(30));
    r_live t_live;
    --
    TYPE t_mon IS RECORD (sid NUMBER, sql_id VARCHAR2(30), exec_id NUMBER, status VARCHAR2(60),
                          mon_start DATE, exec_start DATE, ela NUMBER, cpu NUMBER, bgets NUMBER,
                          dreads NUMBER, rows_out NUMBER, phv NUMBER, wa_mem NUMBER);
    r_mon t_mon;
    --
    TYPE t_sig IS RECORD (sql_id VARCHAR2(20), fms VARCHAR2(40), plans NUMBER, execs NUMBER,
                          first_load VARCHAR2(30), last_active VARCHAR2(30));
    r_sig t_sig;
    --
    TYPE t_awrplan IS RECORD (phv NUMBER, snaps NUMBER, execs NUMBER, avg_ela NUMBER, avg_lio NUMBER,
                              avg_pio NUMBER, first_seen VARCHAR2(20), last_seen VARCHAR2(20));
    r_awrplan t_awrplan;
    --
    TYPE t_cache IS RECORD (child NUMBER, phv NUMBER, execs NUMBER, avg_ela NUMBER, avg_lio NUMBER,
                            avg_pio NUMBER, parses NUMBER, first_load VARCHAR2(30), last_active VARCHAR2(30));
    r_cache t_cache;
    --
    TYPE t_wait IS RECORD (sid NUMBER, serial NUMBER, username VARCHAR2(200), status VARCHAR2(30),
                           state VARCHAR2(30), event VARCHAR2(200), wait_class VARCHAR2(100),
                           sec_in_wait NUMBER, blk_sid NUMBER, blk_inst NUMBER, blk_status VARCHAR2(30),
                           final_blk NUMBER, p1text VARCHAR2(100), p1 NUMBER, p2text VARCHAR2(100),
                           p2 NUMBER, p3text VARCHAR2(100), p3 NUMBER);
    r_wait t_wait;
    TYPE t_wait_tab IS TABLE OF t_wait INDEX BY PLS_INTEGER;
    v_waits t_wait_tab;
    --
    TYPE t_blk IS RECORD (b_sid NUMBER, b_serial NUMBER, b_user VARCHAR2(200), b_event VARCHAR2(200),
                          b_wait NUMBER, k_sid NUMBER, k_serial NUMBER, k_user VARCHAR2(200),
                          k_status VARCHAR2(30), k_event VARCHAR2(200), k_sql VARCHAR2(30),
                          k_prev VARCHAR2(30), k_et NUMBER, k_blocked_by NUMBER, root_sid NUMBER);
    r_blk t_blk;
    --
    TYPE t_ash IS RECORD (event VARCHAR2(300), wclass VARCHAR2(100), samples NUMBER, pct NUMBER);
    r_ash t_ash;
    --
    TYPE t_plan IS RECORD (phv NUMBER, c_exec NUMBER, c_avg NUMBER, c_last DATE, a_snaps NUMBER,
                           a_exec NUMBER, a_avg NUMBER, a_first DATE, a_last DATE);
    r_plan t_plan;
    TYPE t_plan_tab IS TABLE OF t_plan INDEX BY PLS_INTEGER;
    v_plans t_plan_tab;
    --
    TYPE t_child IS RECORD (child NUMBER, phv NUMBER, execs NUMBER, avg_ela NUMBER, env_hash NUMBER,
                            bind_sens VARCHAR2(3), bind_aware VARCHAR2(3), reopt VARCHAR2(3),
                            baseline VARCHAR2(200), profile VARCHAR2(200), patch VARCHAR2(200),
                            schema VARCHAR2(200));
    r_child t_child;
    --
    TYPE t_par IS RECORD (name VARCHAR2(200), vals NUMBER, first_val VARCHAR2(1000), last_val VARCHAR2(1000));
    r_par t_par;
    --
    ---------------------------------------------------------------------------
    -- VARIABLES  (all variables are declared before any subprogram)
    ---------------------------------------------------------------------------
    rc            t_rc;
    q             VARCHAR2(32767);
    v_awr_cte     VARCHAR2(4000);
    v_sql_id      VARCHAR2(30)   := :b_sql_id;
    v_sid         VARCHAR2(30)   := :b_sid;
    v_input       VARCHAR2(100)  := :b_input;
    v_ver         VARCHAR2(100);
    v_n           NUMBER;
    v_n2          NUMBER;
    v_n3          NUMBER;
    v_cnt         PLS_INTEGER;
    v_found       BOOLEAN        := FALSE;
    v_awr_ok      BOOLEAN        := FALSE;
    v_str         VARCHAR2(4000);
    v_str2        VARCHAR2(4000);
    v_line        VARCHAR2(4000);
    v_clob        CLOB;
    v_cache_plan  BOOLEAN        := FALSE;
    v_awr_phv     NUMBER;
    v_in_cursor   NUMBER         := 0;
    v_in_hist     NUMBER         := 0;
    v_fms         NUMBER;
    v_sibl_ids    NUMBER         := 0;
    v_sibl_plans  NUMBER         := 0;
    v_cur_phv     NUMBER;
    v_cur_src     VARCHAR2(100);
    v_cur_idx     PLS_INTEGER;
    v_prev_idx    PLS_INTEGER;
    v_chg_date    DATE;
    v_best        NUMBER;
    v_worst       NUMBER;
    v_best_phv    NUMBER;
    v_worst_phv   NUMBER;
    v_eff         NUMBER;
    v_ts          DATE;
    v_first_all   DATE;
    v_last_all    DATE;
    v_n_plans     PLS_INTEGER   := 0;
    v_children    NUMBER        := 0;
    v_child_envs  NUMBER        := 0;
    v_awr_snaps   NUMBER        := 0;
    v_total_samp  NUMBER        := 0;
    v_findings    PLS_INTEGER   := 0;
    v_src_view    VARCHAR2(30);
    v_full        NUMBER;
    v_cart        NUMBER;
    v_hj          NUMBER;
    v_rowstats    NUMBER;
    v_misest      NUMBER;
    v_spill_ops   NUMBER;
    v_onepass     NUMBER;
    v_multipass   NUMBER;
    v_cause       VARCHAR2(1000);
    v_resol       VARCHAR2(2000);
    v_stat_tabs   NUMBER;
    v_stat_last   DATE;
    v_stat_after  NUMBER;
    v_mism        VARCHAR2(1000);
    v_ox          NUMBER;
    v_om          NUMBER;
    v_ol          NUMBER;
    v_bm          NUMBER;
    v_bq          NUMBER;
    v_rm          NUMBER;
    --
    -- Findings collected while the report runs (printed in section 6, most important first)
    TYPE t_fd IS RECORD (prio PLS_INTEGER, title VARCHAR2(300), evid VARCHAR2(3200), rec VARCHAR2(3200), valid VARCHAR2(2000));
    TYPE t_fd_tab IS TABLE OF t_fd INDEX BY PLS_INTEGER;
    v_fd          t_fd_tab;
    v_nfd         PLS_INTEGER   := 0;
    v_fd_full     BOOLEAN       := FALSE;
    v_pchg_n      PLS_INTEGER   := 0;
    v_pchg_txt    VARCHAR2(2000);
    v_is_plsql    BOOLEAN       := FALSE;
    --
    -- Wait events currently being waited on by sessions running this SQL_ID.
    -- Declared here (before first use); v_sql_id is declared above.
    CURSOR c_waits IS
        SELECT DISTINCT event, wait_class
        FROM   v$session
        WHERE  sql_id = v_sql_id
        AND    state = 'WAITING'
        AND    wait_class IS NOT NULL
        AND    wait_class != 'Idle';
    --
    ---------------------------------------------------------------------------
    -- SUBPROGRAMS : output helpers
    ---------------------------------------------------------------------------
    PROCEDURE p(p_s IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_s);
    END p;
    --
    FUNCTION esc(p_s IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN REPLACE(REPLACE(REPLACE(REPLACE(p_s, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
    END esc;
    --
    FUNCTION nz(p_s IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN NVL(esc(p_s), '-');
    END nz;
    --
    FUNCTION fnum(p_n IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF p_n IS NULL THEN RETURN '-'; END IF;
        RETURN TO_CHAR(p_n, 'FM999,999,999,999,999,990');
    END fnum;
    --
    FUNCTION fdec(p_n IN NUMBER, p_d IN PLS_INTEGER DEFAULT 3) RETURN VARCHAR2 IS
    BEGIN
        IF p_n IS NULL THEN RETURN '-'; END IF;
        RETURN TO_CHAR(ROUND(p_n, p_d), 'FM999,999,999,990.' || RPAD('0', p_d, '0'));
    END fdec;
    --
    FUNCTION fdur(p_sec IN NUMBER) RETURN VARCHAR2 IS
        v_s NUMBER := ROUND(NVL(p_sec, 0));
    BEGIN
        IF p_sec IS NULL THEN RETURN '-'; END IF;
        IF v_s < 60 THEN
            RETURN v_s || ' sec';
        ELSIF v_s < 3600 THEN
            RETURN TRUNC(v_s / 60) || ' min ' || MOD(v_s, 60) || ' sec';
        ELSIF v_s < 86400 THEN
            RETURN TRUNC(v_s / 3600) || ' hr ' || TRUNC(MOD(v_s, 3600) / 60) || ' min';
        ELSE
            RETURN TRUNC(v_s / 86400) || ' day(s) ' || TRUNC(MOD(v_s, 86400) / 3600) || ' hr';
        END IF;
    END fdur;
    --
    FUNCTION fts(p_d IN DATE) RETURN VARCHAR2 IS
    BEGIN
        IF p_d IS NULL THEN RETURN '-'; END IF;
        RETURN TO_CHAR(p_d, 'YYYY-MM-DD HH24:MI:SS');
    END fts;
    --
    FUNCTION badge(p_txt IN VARCHAR2, p_cls IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN '<span class="badge ' || p_cls || '">' || esc(p_txt) || '</span>';
    END badge;
    --
    FUNCTION td(p_s IN VARCHAR2, p_cls IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN '<td' || CASE WHEN p_cls IS NOT NULL THEN ' class="' || p_cls || '"' END || '>' || nz(p_s) || '</td>';
    END td;
    --
    FUNCTION tdh(p_html IN VARCHAR2, p_cls IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN '<td' || CASE WHEN p_cls IS NOT NULL THEN ' class="' || p_cls || '"' END || '>' || NVL(p_html, '-') || '</td>';
    END tdh;
    --
    PROCEDURE h2(p_no IN VARCHAR2, p_t IN VARCHAR2) IS
    BEGIN
        p('<h2><span class="num">' || p_no || '</span> ' || esc(p_t) || '</h2>');
    END h2;
    --
    PROCEDURE h3(p_no IN VARCHAR2, p_t IN VARCHAR2) IS
    BEGIN
        p('<h3>' || p_no || '&nbsp; ' || esc(p_t) || '</h3>');
    END h3;
    --
    PROCEDURE note(p_cls IN VARCHAR2, p_html IN VARCHAR2) IS
    BEGIN
        p('<div class="note ' || p_cls || '">' || p_html || '</div>');
    END note;
    --
    PROCEDURE errnote(p_what IN VARCHAR2, p_err IN VARCHAR2) IS
    BEGIN
        note('warn', esc(p_what) || ' could not be retrieved: <code>' || esc(SUBSTR(p_err, 1, 300)) || '</code>');
    END errnote;
    --
    -- Opens a table. Column titles are separated by "|"; a leading ">" right-aligns the column.
    PROCEDURE tbl_open(p_heads IN VARCHAR2) IS
        v_rest VARCHAR2(4000) := p_heads;
        v_pos  PLS_INTEGER;
        v_out  VARCHAR2(8000) := '<div class="tw"><table class="grid"><thead><tr>';
        v_h    VARCHAR2(500);
    BEGIN
        LOOP
            v_pos := INSTR(v_rest, '|');
            IF v_pos = 0 THEN v_h := v_rest; ELSE v_h := SUBSTR(v_rest, 1, v_pos - 1); END IF;
            IF SUBSTR(v_h, 1, 1) = '>' THEN
                v_out := v_out || '<th class="r">' || esc(SUBSTR(v_h, 2)) || '</th>';
            ELSE
                v_out := v_out || '<th>' || esc(v_h) || '</th>';
            END IF;
            EXIT WHEN v_pos = 0;
            v_rest := SUBSTR(v_rest, v_pos + 1);
        END LOOP;
        p(v_out || '</tr></thead><tbody>');
    END tbl_open;
    --
    PROCEDURE tbl_close IS
    BEGIN
        p('</tbody></table></div>');
    END tbl_close;
    --
    PROCEDURE kv(p_k IN VARCHAR2, p_html IN VARCHAR2) IS
    BEGIN
        p('<tr><th>' || esc(p_k) || '</th><td>' || NVL(p_html, '-') || '</td></tr>');
    END kv;
    --
    -- Prints a CLOB as escaped text lines (for pre blocks). Long lines are cut at a blank.
    PROCEDURE put_lines(p_c IN CLOB, p_max IN NUMBER DEFAULT 5000) IS
        v_len   NUMBER := NVL(DBMS_LOB.GETLENGTH(p_c), 0);
        v_pos   NUMBER := 1;
        v_nl    NUMBER;
        v_s     NUMBER;
        v_piece VARCHAR2(4000);
        v_cut   NUMBER;
        v_cnt2  NUMBER := 0;
    BEGIN
        WHILE v_pos <= v_len AND v_cnt2 < p_max LOOP
            v_nl := DBMS_LOB.INSTR(p_c, CHR(10), v_pos);
            IF v_nl = 0 THEN v_nl := v_len + 1; END IF;
            v_cnt2 := v_cnt2 + 1;
            IF v_nl = v_pos THEN
                p('');
            ELSE
                v_s := v_pos;
                WHILE v_s < v_nl LOOP
                    v_piece := REPLACE(DBMS_LOB.SUBSTR(p_c, LEAST(v_nl - v_s, 1500), v_s), CHR(13), '');
                    IF v_s + 1500 < v_nl AND LENGTH(v_piece) = 1500 THEN
                        v_cut := INSTR(v_piece, ' ', -1);
                        IF v_cut > 300 THEN v_piece := SUBSTR(v_piece, 1, v_cut); END IF;
                    END IF;
                    p(esc(v_piece));
                    v_s := v_s + GREATEST(LENGTH(v_piece), 1);
                END LOOP;
            END IF;
            v_pos := v_nl + 1;
        END LOOP;
        IF v_pos <= v_len THEN
            p('... (output truncated after ' || p_max || ' lines)');
        END IF;
    END put_lines;
    --
    -- Decode helpers
    FUNCTION state_txt(p_state IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE p_state
                   WHEN 'WAITING'             THEN badge('WAITING', 'warn')
                   WHEN 'WAITED SHORT TIME'   THEN badge('RUNNING / ON CPU', 'ok')
                   WHEN 'WAITED KNOWN TIME'   THEN badge('RUNNING / ON CPU', 'ok')
                   WHEN 'WAITED UNKNOWN TIME' THEN badge('RUNNING / ON CPU', 'ok')
                   ELSE badge(NVL(p_state, 'UNKNOWN'), 'mute')
               END;
    END state_txt;
    --
    FUNCTION blk_status_txt(p_s IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE p_s
                   WHEN 'VALID'       THEN '<b>VALID</b><br><span class="small">blocker identified</span>'
                   WHEN 'NO HOLDER'   THEN 'NO HOLDER<br><span class="small">nothing is blocking</span>'
                   WHEN 'NOT IN WAIT' THEN 'NOT IN WAIT<br><span class="small">session is not waiting</span>'
                   WHEN 'UNKNOWN'     THEN 'UNKNOWN<br><span class="small">blocker cannot be determined</span>'
                   WHEN 'GLOBAL'      THEN '<b>GLOBAL</b><br><span class="small">blocker is on another RAC instance</span>'
                   ELSE nz(p_s)
               END;
    END blk_status_txt;
    --
    FUNCTION mode_name(p_m IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE p_m
                   WHEN 0 THEN 'none'
                   WHEN 1 THEN 'null (N)'
                   WHEN 2 THEN 'row-share (SS)'
                   WHEN 3 THEN 'row-exclusive (SX)'
                   WHEN 4 THEN 'share (S)'
                   WHEN 5 THEN 'share row-exclusive (SSX)'
                   WHEN 6 THEN 'exclusive (X)'
                   ELSE TO_CHAR(p_m)
               END;
    END mode_name;
    --
    -- Translates P1/P2/P3 into something readable. Returns NULL when the raw
    -- parameters carry no diagnostic value (latches, network, commit, idle).
    FUNCTION params_txt(r IN t_wait) RETURN VARCHAR2 IS
        v_o VARCHAR2(1000);
    BEGIN
        IF r.event IS NULL OR r.state <> 'WAITING' THEN
            RETURN NULL;
        END IF;
        IF r.event LIKE 'enq:%' THEN
            RETURN 'Lock type ' || CHR(TRUNC(r.p1 / 16777216)) || CHR(MOD(TRUNC(r.p1 / 65536), 256))
                   || ', requested mode ' || mode_name(MOD(r.p1, 65536))
                   || ', id1=' || r.p2 || ', id2=' || r.p3;
        ELSIF r.event IN ('cursor: pin S wait on X', 'library cache: mutex X') THEN
            RETURN 'Mutex holder SID (decoded from P2) = ' || TRUNC(r.p2 / 4294967296) || ', object hash = ' || r.p1;
        ELSIF r.event LIKE 'latch:%' OR r.wait_class IN ('Network', 'Idle', 'Commit') THEN
            RETURN NULL;
        END IF;
        IF r.p1text IS NOT NULL AND r.p1 <> 0 THEN
            v_o := r.p1text || '=' || r.p1;
        END IF;
        IF r.p2text IS NOT NULL AND r.p2 <> 0 THEN
            v_o := v_o || CASE WHEN v_o IS NOT NULL THEN ', ' END || r.p2text || '=' || r.p2;
        END IF;
        IF r.p3text IS NOT NULL AND r.p3 <> 0 THEN
            v_o := v_o || CASE WHEN v_o IS NOT NULL THEN ', ' END || r.p3text || '=' || r.p3;
        END IF;
        RETURN v_o;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN NULL;
    END params_txt;
    --
    -- Wait event -> probable cause / suggested resolution
    PROCEDURE advice(p_event IN VARCHAR2, p_class IN VARCHAR2, o_cause OUT VARCHAR2, o_res OUT VARCHAR2) IS
    BEGIN
        CASE
            WHEN p_event LIKE 'db file sequential read%' THEN
                o_cause := 'Single-block I/O, typically index lookups.';
                o_res   := 'Check index selectivity and storage/IO latency; verify AWR IO latency; consider caching hot blocks.';
            WHEN p_event LIKE 'db file scattered read%' OR p_event LIKE 'direct path read%' THEN
                o_cause := 'Multi-block I/O, typically full table or index scans.';
                o_res   := 'Check for missing indexes or stale statistics; if the scan is legitimate, consider partitioning or parallelism.';
            WHEN p_event LIKE 'enq: TX%' THEN
                o_cause := 'Row lock contention (TX enqueue).';
                o_res   := 'Identify and commit/rollback the blocking session; check for long-running uncommitted DML or unique-key contention.';
            WHEN p_event LIKE 'enq: TM%' THEN
                o_cause := 'DML/DDL table lock contention.';
                o_res   := 'Check for unindexed foreign keys causing full-table locks, or concurrent DDL; add the FK index or serialize the DDL.';
            WHEN p_event LIKE 'latch: cache buffers chains%' THEN
                o_cause := 'Many sessions access the same (hot) buffers; typically excessive logical I/O on a few blocks.';
                o_res   := 'Reduce logical reads of the SQL (plan/index tuning); look for hot blocks; consider hash-partitioning the hot segment or reducing concurrency.';
            WHEN p_event LIKE '%library cache%' OR p_event LIKE 'latch: shared pool%' OR p_event LIKE 'cursor: %' THEN
                o_cause := 'Library cache / shared pool contention, often caused by hard parsing of literal SQL.';
                o_res   := 'Check for literal SQL causing library cache churn; use bind variables; review CURSOR_SHARING.';
            WHEN p_event LIKE '%latch%' OR p_event LIKE '%mutex%' THEN
                o_cause := 'Latch or mutex contention from high concurrency on a shared memory structure.';
                o_res   := 'Identify the latch/mutex name in the event, review the blocking session chain, and reduce concurrency on the structure.';
            WHEN p_event LIKE 'log file sync%' THEN
                o_cause := 'Commit-related wait on LGWR.';
                o_res   := 'Check redo log I/O latency and commit frequency; consider batching commits or faster redo storage.';
            WHEN p_event LIKE 'buffer busy waits%' THEN
                o_cause := 'Contention on the same block, often a hot index leaf block.';
                o_res   := 'Consider a reverse key or hash-partitioned index, or verify ASSM is in use.';
            WHEN p_event LIKE 'gc %' THEN
                o_cause := 'RAC global cache (interconnect) wait.';
                o_res   := 'Check interconnect health and bandwidth; consider service or session affinity.';
            WHEN p_class = 'Network' THEN
                o_cause := 'Network round trips, typically SQL*Net.';
                o_res   := 'Check client array fetch size and network latency between database and client or application tier.';
            WHEN p_class = 'Concurrency' THEN
                o_cause := 'Generic concurrency wait.';
                o_res   := 'Review the blocking session chain above and reduce lock hold duration.';
            ELSE
                o_cause := 'Wait class ' || p_class || ' - no specific pattern known to this script.';
                o_res   := 'Review this wait event in the documentation and cross-check AWR for known patterns.';
        END CASE;
    END advice;
    --
    -- Counts plan rows of the analysed plan in the chosen plan view.
    FUNCTION cnt(p_view IN VARCHAR2, p_where IN VARCHAR2) RETURN NUMBER IS
        v_r NUMBER;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || p_view || ' WHERE sql_id = :1 AND plan_hash_value = :2 AND ' || p_where
            INTO v_r USING v_sql_id, v_cur_phv;
        RETURN v_r;
    END cnt;
    --
    -- Prints the plan text of the already opened cursor RC (DBMS_XPLAN output) as three collapsible
    -- blocks: the plan table, the plan OUTLINE (the hints that reproduce the plan, "Outline Data"
    -- section), and the predicate information / notes that follow it. Closes RC.
    -- o_any = FALSE when DBMS_XPLAN returned nothing usable (nothing is printed in that case).
    PROCEDURE put_xplan(p_open_attr IN VARCHAR2, o_any OUT BOOLEAN) IS
        l_n   PLS_INTEGER := 0;
        l_st  PLS_INTEGER := 0;   -- 0 nothing open, 1 plan, 2 outline, 3 predicates / notes
        l_ol  BOOLEAN     := FALSE;
        l_ln  VARCHAR2(4000);
    BEGIN
        o_any := FALSE;
        LOOP
            FETCH rc INTO l_ln;
            EXIT WHEN rc%NOTFOUND;
            IF l_n = 0 THEN
                IF l_ln LIKE '%cannot fetch plan%' OR l_ln LIKE '%not found%' THEN
                    EXIT;
                END IF;
                o_any := TRUE;
                p('<details' || p_open_attr || '><summary>Show plan</summary><pre>');
                l_st := 1;
            END IF;
            l_n := l_n + 1;
            IF l_st = 1 AND l_ln LIKE 'Outline Data%' THEN
                p('</pre></details>');
                p('<details><summary>Show plan outline (hints that reproduce this plan)</summary><pre>');
                l_st := 2;
                l_ol := TRUE;
            END IF;
            p(esc(l_ln));
            IF l_st = 2 AND TRIM(l_ln) = '*/' THEN
                p('</pre></details>');
                p('<details open><summary>Show predicate information and notes</summary><pre>');
                l_st := 3;
            END IF;
        END LOOP;
        CLOSE rc;
        IF l_st > 0 THEN
            p('</pre></details>');
        END IF;
        IF o_any AND NOT l_ol THEN
            note('info', 'No plan outline was returned for this plan (the stored plan does not carry the OTHER_XML outline data, or the release does not report it).');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF rc%ISOPEN THEN CLOSE rc; END IF;
            IF l_st > 0 THEN p('</pre></details>'); END IF;
            RAISE;
    END put_xplan;
    --
    -- prio: 1 = High, 2 = Review, 3 = Info
    PROCEDURE fd_add(p_prio IN PLS_INTEGER, p_title IN VARCHAR2, p_evid IN VARCHAR2, p_rec IN VARCHAR2, p_valid IN VARCHAR2) IS
    BEGIN
        v_nfd := v_nfd + 1;
        v_fd(v_nfd).prio  := p_prio;
        v_fd(v_nfd).title := SUBSTR(p_title, 1, 300);
        v_fd(v_nfd).evid  := SUBSTR(p_evid, 1, 3200);
        v_fd(v_nfd).rec   := SUBSTR(p_rec, 1, 3200);
        v_fd(v_nfd).valid := SUBSTR(p_valid, 1, 2000);
    END fd_add;
    --
---------------------------------------------------------------------------
BEGIN
---------------------------------------------------------------------------
    -- Is AWR readable? (decides whether AWR based parts are attempted)
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM dba_hist_sqlstat WHERE 1 = 0' INTO v_n;
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM dba_hist_snapshot WHERE 1 = 0' INTO v_n;
        v_awr_ok := TRUE;
    EXCEPTION
        WHEN OTHERS THEN
            v_awr_ok := FALSE;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT version FROM v$instance' INTO v_ver;
    EXCEPTION
        WHEN OTHERS THEN
            v_ver := 'n/a';
    END;
    --
    ------------------------------------------------------------------ HEADER
    p('<!DOCTYPE html>');
    p('<html lang="en"><head><meta charset="utf-8">');
    p('<meta name="viewport" content="width=device-width, initial-scale=1">');
    p('<title>SQL_ID Diagnostic Report - ' || esc(v_sql_id) || '</title><style>');
    p('body{font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:13px;color:#1f2933;background:#eef1f5;margin:0}');
    p('.page{max-width:1300px;margin:0 auto;padding:20px}');
    p('.hdr{background:#1f3a5f;color:#fff;padding:18px 24px;border-radius:6px}');
    p('.hdr h1{margin:0 0 4px 0;font-size:22px}.hdr .sub{opacity:.85}');
    p('.card{background:#fff;border:1px solid #d5dbe3;border-radius:6px;padding:14px 22px 10px 22px;margin:16px 0}');
    p('h2{font-size:17px;color:#1f3a5f;border-bottom:2px solid #1f3a5f;padding-bottom:6px;margin:0 0 12px 0}');
    p('h3{font-size:14px;color:#2c4a73;margin:20px 0 8px 0}');
    p('.num{background:#1f3a5f;color:#fff;border-radius:3px;padding:1px 8px;margin-right:6px}');
    p('table{border-collapse:collapse}.tw{overflow-x:auto;margin:6px 0 12px 0}');
    p('table.grid{width:100%;font-size:12.5px}');
    p('table.grid th{background:#e6ecf3;text-align:left;padding:6px 8px;border:1px solid #c5cfdb;white-space:nowrap}');
    p('table.grid td{padding:5px 8px;border:1px solid #d9e0e8;vertical-align:top;overflow-wrap:anywhere}');
    p('table.grid tbody tr:nth-child(even){background:#f7f9fb}');
    p('th.r,td.r{text-align:right}td.nw{white-space:nowrap}th.grp{text-align:center;background:#cfd9e6}');
    p('table.kv{font-size:12.5px;margin:6px 0 12px 0;min-width:60%}');
    p('table.kv th{background:#e6ecf3;text-align:left;padding:5px 10px;border:1px solid #c5cfdb;width:290px;vertical-align:top}');
    p('table.kv td{padding:5px 10px;border:1px solid #d9e0e8;overflow-wrap:anywhere}');
    p('.badge{display:inline-block;padding:1px 9px;border-radius:10px;font-size:11.5px;font-weight:600;white-space:nowrap}');
    p('.badge.ok{background:#d9f2e1;color:#14622b}.badge.warn{background:#fdecc8;color:#8a5a00}');
    p('.badge.bad{background:#f9d3d3;color:#9b1c1c}.badge.info{background:#d8e8fb;color:#1a4a8a}.badge.mute{background:#e4e7eb;color:#4a5560}');
    p('.note{padding:8px 12px;border-left:4px solid #888;margin:8px 0;border-radius:3px;background:#f3f5f7}');
    p('.note.ok{border-color:#2e9e4f;background:#eaf7ee}.note.warn{border-color:#d99a00;background:#fff6e0}');
    p('.note.bad{border-color:#c53030;background:#fdeaea}.note.info{border-color:#2f6fbf;background:#eaf2fc}');
    p('.verdict{font-size:15px;font-weight:600}');
    p('pre{background:#101820;color:#e6edf3;padding:10px 12px;border-radius:4px;overflow-x:auto;font-size:12px;line-height:1.35;margin:6px 0 12px 0}');
    p('pre.sql{white-space:pre-wrap;overflow-wrap:anywhere}');
    p('h4{font-size:13.5px;color:#2c4a73;margin:22px 0 6px 0;padding-top:8px;border-top:1px dashed #c5cfdb}');
    p('details{margin:6px 0 12px 0}summary{cursor:pointer;font-weight:600;color:#2c4a73;padding:3px 0}');
    p('.bar{background:#e4e7eb;border-radius:3px;height:10px;min-width:90px}.bar span{display:block;height:10px;background:#2f6fbf;border-radius:3px}');
    p('.small{color:#5b6672;font-size:11.5px}code{background:#eef1f5;padding:0 4px;border-radius:3px}');
    p('ul{margin:6px 0 10px 0;padding-left:22px}li{margin:3px 0}.toc a{color:#2c4a73;text-decoration:none}.toc a:hover{text-decoration:underline}');
    p('@media print{body{background:#fff}.card{break-inside:avoid-page}}');
    p('</style></head><body><div class="page">');
    p('<div class="hdr"><h1>SQL_ID Diagnostic Report</h1>');
    p('<div class="sub">SQL_ID <b>' || esc(v_sql_id) || '</b> &nbsp;|&nbsp; Database ' || esc(SYS_CONTEXT('USERENV', 'DB_NAME'))
      || ' &nbsp;|&nbsp; Generated ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || '</div></div>');
    p('<div class="card"><table class="kv">');
    kv('Input provided', esc(v_input));
    kv('Resolved SQL_ID', '<b>' || esc(v_sql_id) || '</b>');
    kv('Related SID', esc(v_sid));
    kv('Database / Instance', esc(SYS_CONTEXT('USERENV', 'DB_NAME')) || ' / ' || esc(SYS_CONTEXT('USERENV', 'INSTANCE_NAME'))
        || ' (Oracle ' || esc(v_ver) || ')');
    kv('Host', esc(SYS_CONTEXT('USERENV', 'SERVER_HOST')));
    kv('Report run by', esc(SYS_CONTEXT('USERENV', 'SESSION_USER')));
    p('</table>');
    p('</div>');
    --
    IF :b_priv IS NOT NULL THEN
        IF NVL(:b_allow_priv, 'N') <> 'Y' THEN
            p('<div class="card">');
            note('bad', '<b>Report not generated.</b> This account holds privileges that can change the database (' || esc(:b_priv)
                        || '). The report only reads, but it must not run under an account that could write. Run it with an account that has SELECT grants only (see the script header). '
                        || 'To override deliberately, set <code>DEFINE allow_privileged = Y</code> at the top of the script.');
            p('</div></div></body></html>');
            RETURN;
        END IF;
    END IF;
    --
    IF v_sql_id IN ('UNKNOWN', 'INVALID') THEN
        p('<div class="card">');
        IF v_sql_id = 'INVALID' THEN
            note('bad', 'The input <b>' || esc(v_input) || '</b> is neither a numeric SID nor a 13-character SQL_ID. Run the script again.');
        ELSE
            note('bad', 'No SQL_ID could be resolved from <b>' || esc(v_input) || '</b> (the session does not exist, or it has neither a current nor a previous SQL_ID).');
        END IF;
        p('</div></div></body></html>');
        RETURN;
    END IF;
    --
    IF NOT v_awr_ok THEN
        note('warn', 'AWR views (DBA_HIST_SQLSTAT / DBA_HIST_SNAPSHOT) are not readable by this user. All historical (AWR/ASH) parts of the report are limited to what is still in memory.');
    END IF;
    --
    -- Is the SQL_ID an anonymous PL/SQL block (COMMAND_TYPE 47)?  Such a SQL_ID has no
    -- execution plan of its own: the statements it runs have their own SQL_IDs.
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM v$sqlarea WHERE sql_id = :1 AND command_type = 47' INTO v_n USING v_sql_id;
        v_is_plsql := v_n > 0;
        IF NOT v_is_plsql AND v_awr_ok THEN
            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM dba_hist_sqltext WHERE sql_id = :1 AND command_type = 47' INTO v_n USING v_sql_id;
            v_is_plsql := v_n > 0;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_is_plsql := FALSE;
    END;
    IF v_is_plsql THEN
        note('warn', '<b>This SQL_ID is an anonymous PL/SQL block</b> (COMMAND_TYPE 47). It has no execution plan of its own, so plan, table/index and plan-based checks do not apply to it. '
                     || 'The SQL statements the block runs have their own SQL_IDs; section 6 lists the ones seen in ASH. Run this script for those SQL_IDs to analyse plans, statistics and fragmentation.');
    END IF;
    --
    --=========================================================================
    -- SECTION 1 : CURRENT EXECUTION STATUS, SQL MONITOR AND EXECUTION PLAN
    --=========================================================================
    p('<div class="card" id="sec1">');
    h2('1', 'Current Execution Status, SQL Monitor and Execution Plan');
    --
    h3('1.1', 'Execution status');
    BEGIN
        EXECUTE IMMEDIATE q'[SELECT COUNT(*) FROM v$session WHERE sql_id = :1 AND status = 'ACTIVE']' INTO v_n USING v_sql_id;
        v_n2 := 0;
        v_str2 := NULL;
        BEGIN
            EXECUTE IMMEDIATE q'[SELECT COUNT(*) FROM v$sql_monitor WHERE sql_id = :1 AND status = 'EXECUTING']' INTO v_n2 USING v_sql_id;
        EXCEPTION
            WHEN OTHERS THEN
                v_n2 := 0;
                v_str2 := SQLERRM;
        END;
        p('<table class="kv">');
        IF v_n > 0 OR v_n2 > 0 THEN
            kv('Result', badge('RUNNING / IN PROGRESS', 'warn') || ' this SQL_ID is executing right now.');
        ELSE
            kv('Result', badge('NOT RUNNING', 'ok') || ' no active session or SQL Monitor entry found.');
        END IF;
        kv('Active sessions executing this SQL_ID', fnum(v_n));
        p('</table>');
    EXCEPTION
        WHEN OTHERS THEN
            errnote('Execution status', SQLERRM);
    END;
    --
    h3('1.2', 'SQL text');
    BEGIN
        v_clob := NULL;
        BEGIN
            EXECUTE IMMEDIATE 'SELECT sql_fulltext FROM v$sqlstats WHERE sql_id = :1 AND ROWNUM = 1' INTO v_clob USING v_sql_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_clob := NULL;
        END;
        IF v_clob IS NULL AND v_awr_ok THEN
            BEGIN
                EXECUTE IMMEDIATE 'SELECT sql_text FROM dba_hist_sqltext WHERE sql_id = :1 AND ROWNUM = 1' INTO v_clob USING v_sql_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_clob := NULL;
            END;
        END IF;
        IF v_clob IS NULL THEN
            note('info', 'SQL text is not available (not in the shared pool and not in AWR).');
        ELSE
            p('<pre class="sql">');
            put_lines(v_clob, 400);
            p('</pre>');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            errnote('SQL text', SQLERRM);
    END;
    --
    h3('1.3', 'Sessions currently running or last run this SQL_ID');
    BEGIN
        q := q'[SELECT s.sid, s.serial#, s.username, s.status, CASE WHEN s.sql_id = :1 THEN 'CURRENT' ELSE 'PREVIOUS' END,
                       s.sql_exec_start, s.last_call_et, s.event, s.wait_class, s.state
                FROM v$session s WHERE s.sql_id = :2 OR s.prev_sql_id = :3
                ORDER BY CASE WHEN s.sql_id = :4 THEN 0 ELSE 1 END, s.sid]';
        v_cnt := 0;
        OPEN rc FOR q USING v_sql_id, v_sql_id, v_sql_id, v_sql_id;
        LOOP
            FETCH rc INTO r_live;
            EXIT WHEN rc%NOTFOUND;
            IF v_cnt = 0 THEN
                tbl_open('>SID|>Serial#|User|Session Status|This SQL_ID is|SQL Exec Start|>In Current State For|Wait Class|Current / Last Wait Event');
            END IF;
            v_cnt := v_cnt + 1;
            p('<tr>' || td(TO_CHAR(r_live.sid), 'r nw') || td(TO_CHAR(r_live.serial), 'r nw')
              || td(NVL(r_live.username, '(background)')) || td(r_live.status)
              || tdh(CASE r_live.rel WHEN 'CURRENT' THEN badge('Current statement', 'warn') ELSE badge('Previous statement', 'mute') END)
              || td(fts(r_live.exec_start), 'nw') || td(fdur(r_live.call_et), 'r nw')
              || td(r_live.wait_class) || td(r_live.event) || '</tr>');
        END LOOP;
        CLOSE rc;
        IF v_cnt = 0 THEN
            note('info', 'No session currently has this SQL_ID as its current or previous statement.');
        ELSE
            tbl_close;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF rc%ISOPEN THEN CLOSE rc; END IF;
            errnote('Session list', SQLERRM);
    END;
    --
    h3('1.4', 'Real-time SQL Monitor summary (10 most recent executions)');
    DECLARE
        l_pack     VARCHAR2(100);
        l_go       BOOLEAN       := TRUE;
        l_rows_x   VARCHAR2(400);
        l_wa_x     VARCHAR2(400);
        l_stat     VARCHAR2(30);
        l_c1       NUMBER;
        l_c2       NUMBER;
        l_c3       NUMBER;
        l_c4       NUMBER;
        --
        FUNCTION col_cnt(p_view IN VARCHAR2, p_cols IN VARCHAR2) RETURN NUMBER IS
            l_n NUMBER;
        BEGIN
            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM all_tab_columns WHERE owner = ''SYS'' AND table_name = :1 AND INSTR('',''||:2||'','', '',''||column_name||'','') > 0'
                INTO l_n USING p_view, p_cols;
            RETURN l_n;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN 0;
        END col_cnt;
    BEGIN
        -- (a) Licence / pack gate. V$SQL_MONITOR is part of the Tuning Pack; when the
        --     pack is switched off we show an informational message, not an ORA- error.
        BEGIN
            EXECUTE IMMEDIATE q'[SELECT UPPER(value) FROM v$parameter WHERE name = 'control_management_pack_access']' INTO l_pack;
        EXCEPTION
            WHEN OTHERS THEN
                l_pack := NULL;   -- parameter not readable / not present: try the query anyway
        END;
        IF l_pack IS NOT NULL AND INSTR(l_pack, 'TUNING') = 0 THEN
            l_go := FALSE;
            note('info', 'SQL Monitor data is not available: <code>CONTROL_MANAGEMENT_PACK_ACCESS</code> is <b>'
                         || esc(l_pack) || '</b> (the Tuning Pack is not enabled, so V$SQL_MONITOR cannot be used). '
                         || 'This is a licensing / configuration setting, not an error in the report.');
        END IF;
        --
        IF l_go THEN
            -- (b) Version compatibility. V$SQL_MONITOR has NO memory column (PGA_ALLOCATED does not
            --     exist there; that was the cause of ORA-00904). Memory and row counts are derived
            --     from V$SQL_PLAN_MONITOR (joined on KEY) when its columns exist in this release.
            --     V$SQL_MONITOR columns used below exist from 11.2 onwards.
            l_c1 := col_cnt('V_$SQL_PLAN_MONITOR', 'KEY,PLAN_LINE_ID,OUTPUT_ROWS');
            l_c2 := col_cnt('V_$SQL_PLAN_MONITOR', 'KEY,WORKAREA_MAX_MEM');
            l_rows_x := CASE WHEN l_c1 = 3
                             THEN '(SELECT MAX(pm.output_rows) FROM v$sql_plan_monitor pm WHERE pm.key = m.key AND pm.plan_line_id = 0)'
                             ELSE 'TO_NUMBER(NULL)' END;
            l_wa_x   := CASE WHEN l_c2 = 2
                             THEN '(SELECT SUM(pm.workarea_max_mem) / 1048576 FROM v$sql_plan_monitor pm WHERE pm.key = m.key)'
                             ELSE 'TO_NUMBER(NULL)' END;
            --
            q := 'SELECT * FROM (SELECT m.sid, m.sql_id, m.sql_exec_id, m.status, m.first_refresh_time, m.sql_exec_start,'
              || ' m.elapsed_time / 1000000, m.cpu_time / 1000000, m.buffer_gets, m.disk_reads, '
              || l_rows_x || ', m.sql_plan_hash_value, ' || l_wa_x
              || ' FROM v$sql_monitor m WHERE m.sql_id = :1'
              || ' ORDER BY m.sql_exec_start DESC NULLS LAST, m.sql_exec_id DESC NULLS LAST) WHERE ROWNUM <= 10';
            v_cnt := 0;
            OPEN rc FOR q USING v_sql_id;
            LOOP
                FETCH rc INTO r_mon;
                EXIT WHEN rc%NOTFOUND;
                IF v_cnt = 0 THEN
                    tbl_open('>SID|SQL_ID|>SQL Exec ID|Status|Monitoring Start|SQL Exec Start|>Elapsed (s)|>CPU (s)|>Buffer Gets|>Physical Reads (blocks)|>Rows Processed|>Plan Hash Value|>Work Area Max (MB)');
                END IF;
                v_cnt := v_cnt + 1;
                p('<tr>' || td(TO_CHAR(r_mon.sid), 'r') || td(r_mon.sql_id, 'nw') || td(TO_CHAR(r_mon.exec_id), 'r')
                  || td(r_mon.status) || td(fts(r_mon.mon_start), 'nw') || td(fts(r_mon.exec_start), 'nw')
                  || td(fdec(r_mon.ela, 2), 'r') || td(fdec(r_mon.cpu, 2), 'r')
                  || td(fnum(r_mon.bgets), 'r') || td(fnum(r_mon.dreads), 'r') || td(fnum(r_mon.rows_out), 'r')
                  || td(TO_CHAR(r_mon.phv), 'r nw') || td(fdec(r_mon.wa_mem, 2), 'r') || '</tr>');
            END LOOP;
            CLOSE rc;
            IF v_cnt = 0 THEN
                BEGIN
                    EXECUTE IMMEDIATE q'[SELECT UPPER(value) FROM v$parameter WHERE name = 'statistics_level']' INTO l_stat;
                EXCEPTION
                    WHEN OTHERS THEN
                        l_stat := NULL;
                END;
                note('info', 'No SQL Monitor entries exist for this SQL_ID. A statement is monitored only when it runs in parallel, '
                             || 'uses the MONITOR hint, or consumes more than 5 seconds of CPU or I/O time; DML, queries and '
                             || 'PL/SQL blocks are eligible, but very short statements are not. Entries also age out of the '
                             || 'shared pool, and monitoring needs <code>STATISTICS_LEVEL</code> = TYPICAL or ALL'
                             || CASE WHEN l_stat IS NOT NULL THEN ' (currently <b>' || esc(l_stat) || '</b>)' END || '.');
            ELSE
                tbl_close;
            END IF;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF rc%ISOPEN THEN CLOSE rc; END IF;
            IF SQLCODE IN (-942, -1031, -1039) THEN
                -- missing object / insufficient privilege: informational, not an error
                note('info', 'SQL Monitor summary is not available to this user (' || esc(SUBSTR(SQLERRM, 1, 150))
                             || '). Grant SELECT on V$SQL_MONITOR and V$SQL_PLAN_MONITOR directly to the user and confirm the Tuning Pack is licensed.');
            ELSE
                errnote('SQL Monitor summary (requires Tuning Pack)', SQLERRM);
            END IF;
    END;
    --
    h3('1.5', 'SQL Monitor report (text)');
    BEGIN
        EXECUTE IMMEDIATE q'[SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(sql_id => :1, report_level => 'ALL', type => 'TEXT') FROM dual]'
            INTO v_clob USING v_sql_id;
        IF v_clob IS NULL OR DBMS_LOB.GETLENGTH(v_clob) < 50 THEN
            note('info', 'DBMS_SQLTUNE returned no monitor report for this SQL_ID.');
        ELSE
            p('<details><summary>Show SQL Monitor report</summary><pre>');
            put_lines(v_clob, 3000);
            p('</pre></details>');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            errnote('SQL Monitor report (requires Tuning Pack)', SQLERRM);
    END;
    --
    -- 1.5.1 / 1.5.2 : bind variable information (read-only SELECTs; switched off by show_binds = N)
    p('<h4>1.5.1&nbsp; Bind variables of the monitored executions</h4>');
    IF NVL(:b_show_binds, 'Y') <> 'Y' THEN
        note('info', 'Bind values are not shown because <code>show_binds = N</code> is set at the top of the script.');
    ELSE
        DECLARE
            l_eid    NUMBER;
            l_est    DATE;
            l_stat   VARCHAR2(60);
            l_pos    NUMBER;
            l_nm     VARCHAR2(128);
            l_dt     VARCHAR2(60);
            l_val    VARCHAR2(4000);
            l_n      PLS_INTEGER := 0;
            l_prev   NUMBER;
            l_new    BOOLEAN;
        BEGIN
            -- V$SQL_MONITOR.BINDS_XML holds the bind values that were actually used by each monitored
            -- execution (Tuning Pack), so they are the values of the run, not of the first parse.
            OPEN rc FOR q'[SELECT * FROM (
                             SELECT m.sql_exec_id, m.sql_exec_start, m.status, b.pos, b.name, b.dtystr, b.val
                             FROM   v$sql_monitor m,
                                    XMLTABLE('/binds/bind' PASSING XMLTYPE(m.binds_xml)
                                             COLUMNS pos NUMBER PATH '@pos', name VARCHAR2(128) PATH '@name',
                                                     dtystr VARCHAR2(60) PATH '@dtystr', val VARCHAR2(4000) PATH '.') b
                             WHERE  m.sql_id = :1 AND m.binds_xml IS NOT NULL
                             ORDER  BY m.sql_exec_start DESC NULLS LAST, m.sql_exec_id DESC, b.pos)
                           WHERE ROWNUM <= 200]' USING v_sql_id;
            LOOP
                FETCH rc INTO l_eid, l_est, l_stat, l_pos, l_nm, l_dt, l_val;
                EXIT WHEN rc%NOTFOUND;
                IF l_n = 0 THEN
                    tbl_open('>SQL Exec ID|SQL Exec Start|Status|>Position|Bind Name|Data Type|Value Used');
                END IF;
                l_n := l_n + 1;
                l_new := (l_n = 1) OR (NVL(l_eid, -1) <> NVL(l_prev, -1));
                p('<tr>' || td(CASE WHEN l_new THEN TO_CHAR(l_eid) END, 'r nw')
                  || td(CASE WHEN l_new THEN fts(l_est) END, 'nw')
                  || td(CASE WHEN l_new THEN l_stat END)
                  || td(TO_CHAR(l_pos), 'r') || td(l_nm, 'nw') || td(l_dt, 'nw')
                  || tdh(CASE WHEN l_val IS NULL THEN '<span class="small">NULL / not recorded</span>' ELSE '<code>' || esc(l_val) || '</code>' END) || '</tr>');
                l_prev := l_eid;
            END LOOP;
            CLOSE rc;
            IF l_n = 0 THEN
                note('info', 'No bind values were recorded by SQL Monitor for this SQL_ID: the statement has no bind variables, was not monitored, '
                             || 'or the monitor entry has aged out. See 1.5.2 for the binds captured by the optimizer.');
            ELSE
                tbl_close;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF rc%ISOPEN THEN CLOSE rc; END IF;
                IF SQLCODE IN (-942, -1031, -904) THEN
                    note('info', 'Bind values of monitored executions are not available to this user or release (' || esc(SUBSTR(SQLERRM, 1, 150)) || ').');
                ELSE
                    errnote('Bind variables of monitored executions', SQLERRM);
                END IF;
        END;
    --
        p('<h4>1.5.2&nbsp; Bind variables captured by the optimizer (V$SQL_BIND_CAPTURE)</h4>');
        DECLARE
            l_child  NUMBER;
            l_pos    NUMBER;
            l_nm     VARCHAR2(128);
            l_dt     VARCHAR2(60);
            l_cap    VARCHAR2(3);
            l_last   DATE;
            l_val    VARCHAR2(4000);
            l_n      PLS_INTEGER := 0;
            l_nocap  PLS_INTEGER := 0;
        BEGIN
            -- The optimizer captures bind values only at hard parse and then about every 15 minutes
            -- (_cursor_bind_capture_interval) while the statement runs, so these are samples.
            OPEN rc FOR q'[SELECT * FROM (SELECT child_number, position, name, datatype_string, was_captured, last_captured, value_string
                           FROM v$sql_bind_capture WHERE sql_id = :1 ORDER BY child_number, position) WHERE ROWNUM <= 200]' USING v_sql_id;
            LOOP
                FETCH rc INTO l_child, l_pos, l_nm, l_dt, l_cap, l_last, l_val;
                EXIT WHEN rc%NOTFOUND;
                IF l_n = 0 THEN
                    tbl_open('>Child #|>Position|Bind Name|Data Type|Captured?|Last Captured|Captured Value');
                END IF;
                l_n := l_n + 1;
                IF NVL(l_cap, 'NO') <> 'YES' THEN l_nocap := l_nocap + 1; END IF;
                p('<tr>' || td(TO_CHAR(l_child), 'r') || td(TO_CHAR(l_pos), 'r') || td(l_nm, 'nw') || td(l_dt, 'nw')
                  || tdh(CASE WHEN l_cap = 'YES' THEN badge('YES', 'ok') ELSE badge('NO', 'mute') END, 'nw')
                  || td(fts(l_last), 'nw')
                  || tdh(CASE WHEN l_cap = 'YES' THEN CASE WHEN l_val IS NULL THEN '<span class="small">NULL</span>' ELSE '<code>' || esc(l_val) || '</code>' END
                              ELSE '<span class="small">not captured</span>' END) || '</tr>');
            END LOOP;
            CLOSE rc;
            IF l_n = 0 THEN
                note('info', 'No bind variables are recorded for this SQL_ID in V$SQL_BIND_CAPTURE: the statement has no bind variables, uses literals, or its cursor is no longer in the shared pool.');
            ELSE
                tbl_close;
                IF l_nocap > 0 THEN
                    note('info', fnum(l_nocap) || ' bind(s) show Captured? = NO. Oracle does not capture binds of some types (for example LOBs, long values) or beyond the capture size limit, and captures only at parse and at intervals, so a value can be missing.');
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF rc%ISOPEN THEN CLOSE rc; END IF;
                errnote('Captured bind variables', SQLERRM);
        END;
    END IF;
    --
    h3('1.6','Execution plan from the cursor cache (with actual statistics when available)');
    BEGIN
        v_cache_plan := FALSE;
        -- +PEEKED_BINDS adds the bind values the optimizer peeked at when it built the plan
        v_str := 'ALLSTATS LAST +OUTLINE' || CASE WHEN NVL(:b_show_binds, 'Y') = 'Y' THEN ' +PEEKED_BINDS' END;
        OPEN rc FOR q'[SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(:1, NULL, :2))]' USING v_sql_id, v_str;
        put_xplan(' open', v_cache_plan);
        IF NOT v_cache_plan THEN
            note('info', 'The cursor is no longer in the shared pool, so no cached plan is available.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF rc%ISOPEN THEN CLOSE rc; END IF;
            errnote('Cursor cache plan', SQLERRM);
    END;
    --
    h3('1.7', 'Execution plan from AWR (most recent plan_hash_value)');
    IF NOT v_awr_ok THEN
        note('info', 'AWR is not accessible.');
    ELSE
        BEGIN
            v_awr_phv := NULL;
            v_cnt := 0;
            BEGIN
                EXECUTE IMMEDIATE 'SELECT plan_hash_value FROM (SELECT plan_hash_value FROM dba_hist_sqlstat WHERE sql_id = :1 ORDER BY snap_id DESC) WHERE ROWNUM = 1'
                    INTO v_awr_phv USING v_sql_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_awr_phv := NULL;
            END;
            IF v_awr_phv IS NULL THEN
                note('info', 'No AWR plan history found for this SQL_ID.');
            ELSE
                p('<p class="small">Most recent AWR plan_hash_value: <b>' || v_awr_phv || '</b></p>');
                OPEN rc FOR q'[SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY_AWR(:1, :2, NULL, 'ALL +OUTLINE'))]' USING v_sql_id, v_awr_phv;
                put_xplan(CASE WHEN NOT v_cache_plan THEN ' open' END, v_found);
                IF NOT v_found THEN
                    note('info', 'DBMS_XPLAN returned no AWR plan text for plan hash value ' || v_awr_phv || '.');
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF rc%ISOPEN THEN CLOSE rc; END IF;
                errnote('AWR plan', SQLERRM);
        END;
    END IF;
    p('</div>');
    --
    --=========================================================================
    -- SECTION 2 : NEW SQL_ID CHECK AND FORCE_MATCHING_SIGNATURE
    --=========================================================================
    p('<div class="card" id="sec2">');
    h2('2', 'New SQL_ID Check and Force Matching Signature');
    --
    -- Signature of the analysed SQL_ID (V$SQLSTATS first, AWR as fallback)
    v_fms := NULL;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT force_matching_signature FROM v$sqlstats WHERE sql_id = :1 AND force_matching_signature != 0 AND ROWNUM = 1'
            INTO v_fms USING v_sql_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_fms := NULL;
    END;
    IF v_fms IS NULL AND v_awr_ok THEN
        BEGIN
            EXECUTE IMMEDIATE 'SELECT force_matching_signature FROM dba_hist_sqlstat WHERE sql_id = :1 AND force_matching_signature != 0 AND ROWNUM = 1'
                INTO v_fms USING v_sql_id;
        EXCEPTION
            WHEN OTHERS THEN
                v_fms := NULL;
        END;
    END IF;
    --
    h3('2.1', 'History check');
    BEGIN
        v_in_cursor := 0;
        v_in_hist := 0;
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM v$sql WHERE sql_id = :1' INTO v_in_cursor USING v_sql_id;
        IF v_awr_ok THEN
            BEGIN
                EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM dba_hist_sqlstat WHERE sql_id = :1' INTO v_in_hist USING v_sql_id;
            EXCEPTION
                WHEN OTHERS THEN
                    v_in_hist := -1;
            END;
        ELSE
            v_in_hist := -1;
        END IF;
        p('<table class="kv">');
        IF v_in_cursor = 0 AND v_in_hist <= 0 THEN
            kv('Result', badge('NEW SQL_ID', 'info') || ' no entry in the cursor cache or AWR history.');
        ELSE
            kv('Result', badge('NOT NEW', 'ok') || ' the SQL_ID has been seen before.');
        END IF;
        kv('Child cursors in cursor cache (V$SQL)', fnum(v_in_cursor));
        kv('Rows in AWR history (DBA_HIST_SQLSTAT)', CASE WHEN v_in_hist = -1 THEN 'not available' ELSE fnum(v_in_hist) END);
        kv('FORCE_MATCHING_SIGNATURE', CASE WHEN v_fms IS NULL THEN 'not applicable (0 or not found) - text is not force-matchable, or the SQL_ID is in neither V$SQLSTATS nor AWR'
                                           ELSE '<code>' || TO_CHAR(v_fms) || '</code>' END);
        p('</table>');
    EXCEPTION
        WHEN OTHERS THEN
            errnote('History check', SQLERRM);
    END;
    --
    h3('2.2', 'SQL_IDs sharing the same FORCE_MATCHING_SIGNATURE');
    IF v_fms IS NULL THEN
        note('info', 'No usable FORCE_MATCHING_SIGNATURE for this SQL_ID, so sibling statements cannot be listed.');
    ELSE
        BEGIN
            q := q'[SELECT s.sql_id, TO_CHAR(s.force_matching_signature), COUNT(DISTINCT s.plan_hash_value), SUM(s.executions),
                           MIN(REPLACE(a.first_load_time, '/', ' ')), TO_CHAR(MAX(s.last_active_time), 'YYYY-MM-DD HH24:MI:SS')
                    FROM v$sqlstats s LEFT JOIN v$sqlarea a ON a.sql_id = s.sql_id
                    WHERE s.force_matching_signature = :1 AND s.force_matching_signature != 0
                    GROUP BY s.sql_id, s.force_matching_signature
                    ORDER BY MIN(a.first_load_time) DESC NULLS LAST, MAX(s.last_active_time) DESC]';
            v_cnt := 0;
            OPEN rc FOR q USING v_fms;
            LOOP
                FETCH rc INTO r_sig;
                EXIT WHEN rc%NOTFOUND;
                IF v_cnt = 0 THEN
                    tbl_open('SQL_ID|Force Matching Signature|>Distinct Plans|>Executions|First Load Time|Last Active Time');
                END IF;
                v_cnt := v_cnt + 1;
                p('<tr>' || tdh(esc(r_sig.sql_id) || CASE WHEN r_sig.sql_id = v_sql_id THEN ' ' || badge('analysed', 'info') END, 'nw')
                  || td(r_sig.fms, 'nw') || td(fnum(r_sig.plans), 'r') || td(fnum(r_sig.execs), 'r')
                  || td(NVL(r_sig.first_load, 'not in cache (aged out)'), 'nw') || td(r_sig.last_active, 'nw') || '</tr>');
            END LOOP;
            CLOSE rc;
            IF v_cnt = 0 THEN
                note('info', 'The signature was found in AWR only; no matching rows remain in V$SQLSTATS.');
            ELSE
                tbl_close;
                IF v_cnt = 1 THEN
                    note('info', 'Only this SQL_ID currently has this signature in V$SQLSTATS.');
                ELSE
                    note('info', fnum(v_cnt) || ' SQL_IDs share this signature, i.e. they differ only in literal values.');
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF rc%ISOPEN THEN CLOSE rc; END IF;
                errnote('Signature lookup', SQLERRM);
        END;
    END IF;
    p('</div>');
    --
    --=========================================================================
    -- SECTION 3 : EXECUTION HISTORY
    --=========================================================================
    p('<div class="card" id="sec3">');
    h2('3', 'Execution History - Plan Hash, Average Elapsed, Average Logical I/O');
    --
    h3('3.1', 'AWR history grouped by plan (shows plan flips, if any)');
    IF NOT v_awr_ok THEN
        note('info', 'AWR is not accessible.');
    ELSE
        BEGIN
            q := q'[SELECT h.plan_hash_value, COUNT(*), SUM(h.executions_delta),
                           ROUND(SUM(h.elapsed_time_delta) / 1000000 / NULLIF(SUM(h.executions_delta), 0), 3),
                           ROUND(SUM(h.buffer_gets_delta) / NULLIF(SUM(h.executions_delta), 0), 1),
                           ROUND(SUM(h.disk_reads_delta) / NULLIF(SUM(h.executions_delta), 0), 1),
                           TO_CHAR(MIN(s.begin_interval_time), 'YYYY-MM-DD HH24:MI'), TO_CHAR(MAX(s.end_interval_time), 'YYYY-MM-DD HH24:MI')
                    FROM dba_hist_sqlstat h JOIN dba_hist_snapshot s
                      ON s.snap_id = h.snap_id AND s.dbid = h.dbid AND s.instance_number = h.instance_number
                    WHERE h.sql_id = :1
                    GROUP BY h.plan_hash_value
                    ORDER BY MAX(s.end_interval_time) DESC]';
            v_cnt := 0;
            OPEN rc FOR q USING v_sql_id;
            LOOP
                FETCH rc INTO r_awrplan;
                EXIT WHEN rc%NOTFOUND;
                IF v_cnt = 0 THEN
                    tbl_open('>Plan Hash Value|>Snapshots|>Executions|>Avg Elapsed (s)|>Avg Buffer Gets|>Avg Disk Reads|First Seen|Last Seen');
                END IF;
                v_cnt := v_cnt + 1;
                p('<tr>' || td(TO_CHAR(r_awrplan.phv), 'r nw') || td(fnum(r_awrplan.snaps), 'r') || td(fnum(r_awrplan.execs), 'r')
                  || td(fdec(r_awrplan.avg_ela, 3), 'r') || td(fnum(r_awrplan.avg_lio), 'r') || td(fnum(r_awrplan.avg_pio), 'r')
                  || td(r_awrplan.first_seen, 'nw') || td(r_awrplan.last_seen, 'nw') || '</tr>');
            END LOOP;
            CLOSE rc;
            IF v_cnt = 0 THEN
                note('info', 'No AWR history for this SQL_ID.');
            ELSE
                tbl_close;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF rc%ISOPEN THEN CLOSE rc; END IF;
                errnote('AWR execution history', SQLERRM);
        END;
    END IF;
    --
    h3('3.2', 'Current in-memory cursor statistics (V$SQL)');
    BEGIN
        q := q'[SELECT child_number, plan_hash_value, executions, ROUND(elapsed_time / 1000000 / NULLIF(executions, 0), 3),
                       ROUND(buffer_gets / NULLIF(executions, 0), 1), ROUND(disk_reads / NULLIF(executions, 0), 1), parse_calls,
                       REPLACE(first_load_time, '/', ' '), TO_CHAR(last_active_time, 'YYYY-MM-DD HH24:MI:SS')
                FROM v$sql WHERE sql_id = :1 ORDER BY child_number]';
        v_cnt := 0;
        OPEN rc FOR q USING v_sql_id;
        LOOP
            FETCH rc INTO r_cache;
            EXIT WHEN rc%NOTFOUND;
            IF v_cnt = 0 THEN
                tbl_open('>Child #|>Plan Hash Value|>Executions|>Avg Elapsed (s)|>Avg Buffer Gets|>Avg Disk Reads|>Parse Calls|First Load Time|Last Active Time');
            END IF;
            v_cnt := v_cnt + 1;
            p('<tr>' || td(TO_CHAR(r_cache.child), 'r') || td(TO_CHAR(r_cache.phv), 'r nw') || td(fnum(r_cache.execs), 'r')
              || td(fdec(r_cache.avg_ela, 3), 'r') || td(fnum(r_cache.avg_lio), 'r') || td(fnum(r_cache.avg_pio), 'r')
              || td(fnum(r_cache.parses), 'r') || td(r_cache.first_load, 'nw') || td(r_cache.last_active, 'nw') || '</tr>');
        END LOOP;
        CLOSE rc;
        IF v_cnt = 0 THEN
            note('info', 'The SQL_ID is not in the shared pool.');
        ELSE
            tbl_close;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF rc%ISOPEN THEN CLOSE rc; END IF;
            errnote('Cursor statistics', SQLERRM);
    END;
    p('</div>');
    --
    --=========================================================================
    -- SECTION 4 : BLOCKING AND WAIT EVENT ANALYSIS
    --=========================================================================
    p('<div class="card" id="sec4">');
    h2('4', 'Blocking and Wait Event Analysis');
    --
    ---------------------------------------------------------- 4.1 current waits
    h3('4.1', 'Current waits for sessions running this SQL_ID');
    BEGIN
        q := q'[SELECT s.sid, s.serial#, s.username, s.status, s.state, s.event, s.wait_class, s.seconds_in_wait,
                       s.blocking_session, s.blocking_instance, s.blocking_session_status, s.final_blocking_session,
                       s.p1text, s.p1, s.p2text, s.p2, s.p3text, s.p3
                FROM v$session s WHERE s.sql_id = :1
                ORDER BY CASE s.state WHEN 'WAITING' THEN 0 ELSE 1 END, s.seconds_in_wait DESC, s.sid]';
        v_waits.DELETE;
        v_cnt := 0;
        OPEN rc FOR q USING v_sql_id;
        LOOP
            FETCH rc INTO r_wait;
            EXIT WHEN rc%NOTFOUND;
            v_cnt := v_cnt + 1;
            v_waits(v_cnt) := r_wait;
        END LOOP;
        CLOSE rc;
    --
        IF v_cnt = 0 THEN
            note('info', '<b>No sessions are currently executing this SQL_ID</b>, so there are no current waits to report.');
        ELSE
            v_n := 0;   -- sessions waiting
            v_n2 := 0;  -- sessions blocked
            FOR i IN 1 .. v_cnt LOOP
                IF v_waits(i).state = 'WAITING' AND v_waits(i).wait_class <> 'Idle' THEN v_n := v_n + 1; END IF;
                IF v_waits(i).blk_sid IS NOT NULL THEN v_n2 := v_n2 + 1; END IF;
            END LOOP;
            IF v_n = 0 THEN
                note('ok', fnum(v_cnt) || ' session(s) running this SQL_ID, <b>none is currently waiting</b> (all are working on CPU). The event shown for such sessions is only the last completed wait.');
            ELSIF v_n2 > 0 THEN
                note('bad', fnum(v_cnt) || ' session(s) running this SQL_ID: ' || fnum(v_n) || ' waiting, <b>' || fnum(v_n2) || ' blocked by another session</b>.');
            ELSE
                note('warn', fnum(v_cnt) || ' session(s) running this SQL_ID: ' || fnum(v_n) || ' currently waiting, none blocked by another session.');
            END IF;
    --
            tbl_open('>SID|>Serial#|User|Session Status|State|Wait Class|Wait Event|>Wait Duration|Blocked?|>Blocking SID|Blocking Status|Wait Parameters (decoded)');
            FOR i IN 1 .. v_cnt LOOP
                r_wait := v_waits(i);
                p('<tr>' || td(TO_CHAR(r_wait.sid), 'r nw') || td(TO_CHAR(r_wait.serial), 'r nw')
                  || td(NVL(r_wait.username, '(background)')) || td(r_wait.status)
                  || tdh(state_txt(r_wait.state), 'nw')
                  || CASE WHEN r_wait.state = 'WAITING'
                          THEN td(r_wait.wait_class) || td(r_wait.event)
                          ELSE td('-') || tdh('<span class="small">not currently waiting; last wait: ' || nz(r_wait.event) || '</span>')
                     END
                  || td(CASE WHEN r_wait.state = 'WAITING' THEN fdur(r_wait.sec_in_wait) END, 'r nw')
                  || tdh(CASE WHEN r_wait.blk_sid IS NOT NULL THEN badge('BLOCKED', 'bad') ELSE badge('No', 'ok') END, 'nw')
                  || tdh(CASE WHEN r_wait.blk_sid IS NULL THEN NULL
                              ELSE '<b>' || r_wait.blk_sid || '</b>'
                                   || CASE WHEN r_wait.blk_inst IS NOT NULL THEN ' (instance ' || r_wait.blk_inst || ')' END
                                   || CASE WHEN r_wait.final_blk IS NOT NULL AND r_wait.final_blk <> r_wait.blk_sid
                                           THEN '<br><span class="small">root blocker SID ' || r_wait.final_blk || '</span>' END
                         END, 'r')
                  || tdh(blk_status_txt(r_wait.blk_status))
                  || td(params_txt(r_wait))
                  || '</tr>');
            END LOOP;
            tbl_close;
            p('<p class="small">Wait duration and wait event are shown only for sessions in state WAITING; any other session is working. Blocking SID is filled only while a session is blocked.</p>');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF rc%ISOPEN THEN CLOSE rc; END IF;
            errnote('Current waits', SQLERRM);
    END;
    --
    ------------------------------------------------------- 4.2 blocking chain
    h3('4.2', 'Blocking chain: who is blocking, and what are they doing');
    BEGIN
        q := q'[SELECT blocked.sid, blocked.serial#, blocked.username, blocked.event, blocked.seconds_in_wait,
                       blocker.sid, blocker.serial#, blocker.username, blocker.status, blocker.event, blocker.sql_id,
                       blocker.prev_sql_id, blocker.last_call_et, blocker.blocking_session, blocked.final_blocking_session
                FROM v$session blocked JOIN v$session blocker ON blocker.sid = blocked.blocking_session
                WHERE blocked.sql_id = :1
                ORDER BY blocked.seconds_in_wait DESC, blocked.sid]';
        v_cnt := 0;
        OPEN rc FOR q USING v_sql_id;
        LOOP
            FETCH rc INTO r_blk;
            EXIT WHEN rc%NOTFOUND;
            IF v_cnt = 0 THEN
                p('<div class="tw"><table class="grid"><thead>');
                p('<tr><th class="grp" colspan="5">BLOCKED SESSION</th><th class="grp" colspan="4">&rarr; BLOCKING SESSION</th>'
                  || '<th class="grp" colspan="3">&rarr; BLOCKING ACTIVITY</th></tr>');
                p('<tr><th class="r">Blocked SID</th><th class="r">Serial#</th><th>Blocked User</th><th>Waiting On</th><th class="r">Waiting For</th>'
                  || '<th class="r">Blocking SID</th><th class="r">Serial#</th><th>Blocking User</th><th>Blocking Status</th>'
                  || '<th>SQL_ID of Blocker</th><th>Current Event / Activity</th><th class="r">In State For</th></tr></thead><tbody>');
            END IF;
            v_cnt := v_cnt + 1;
            p('<tr>' || td(TO_CHAR(r_blk.b_sid), 'r nw') || td(TO_CHAR(r_blk.b_serial), 'r nw')
              || td(NVL(r_blk.b_user, '(background)')) || td(r_blk.b_event) || td(fdur(r_blk.b_wait), 'r nw')
              || tdh('<b>' || r_blk.k_sid || '</b>'
                     || CASE WHEN r_blk.root_sid IS NOT NULL AND r_blk.root_sid <> r_blk.k_sid
                             THEN '<br><span class="small">root blocker SID ' || r_blk.root_sid || '</span>' END, 'nw')
              || td(TO_CHAR(r_blk.k_serial), 'r nw') || td(NVL(r_blk.k_user, '(background)'))
              || tdh(CASE r_blk.k_status WHEN 'ACTIVE' THEN badge('ACTIVE', 'warn')
                                         WHEN 'INACTIVE' THEN badge('INACTIVE (idle)', 'mute')
                                         ELSE badge(NVL(r_blk.k_status, 'UNKNOWN'), 'mute') END, 'nw')
              || tdh(CASE WHEN r_blk.k_sql IS NOT NULL THEN esc(r_blk.k_sql)
                          WHEN r_blk.k_prev IS NOT NULL THEN '<span class="small">last: ' || esc(r_blk.k_prev) || '</span>'
                     END, 'nw')
              || tdh(CASE WHEN r_blk.k_status = 'ACTIVE' THEN 'Executing; current event: ' || nz(r_blk.k_event)
                          WHEN r_blk.k_status = 'INACTIVE' THEN 'Idle, no call in progress. An idle session that still holds a lock usually has an open (uncommitted) transaction.'
                          ELSE nz(r_blk.k_event) END
                     || CASE WHEN r_blk.k_blocked_by IS NOT NULL THEN '<br>The blocker is itself blocked by SID ' || r_blk.k_blocked_by END)
              || td(fdur(r_blk.k_et), 'r nw') || '</tr>');
        END LOOP;
        CLOSE rc;
        IF v_cnt = 0 THEN
            EXECUTE IMMEDIATE q'[SELECT COUNT(*) FROM v$session WHERE sql_id = :1 AND blocking_session_status = 'GLOBAL']' INTO v_n USING v_sql_id;
            IF v_n > 0 THEN
                note('warn', '<b>' || fnum(v_n) || ' session(s) are blocked by a session on another RAC instance</b>; V$SESSION cannot show it. Query GV$SESSION for the blocker.');
            ELSE
                note('ok', '<b>No blocking session detected.</b>');
            END IF;
        ELSE
            tbl_close;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF rc%ISOPEN THEN CLOSE rc; END IF;
            errnote('Blocking chain', SQLERRM);
    END;
    --
    ------------------------------------------- 4.3 wait-class resolution guidance
    h3('4.3', 'Wait-class resolution guidance (for waits happening right now)');
    BEGIN
        v_found := FALSE;
        FOR r IN c_waits LOOP
            IF NOT v_found THEN
                tbl_open('Wait Event|Wait Class|Probable Cause|Suggested Resolution');
            END IF;
            v_found := TRUE;
            advice(r.event, r.wait_class, v_cause, v_resol);
            p('<tr>' || td(r.event) || td(r.wait_class) || td(v_cause) || td(v_resol) || '</tr>');
        END LOOP;
        IF v_found THEN
            tbl_close;
        ELSE
            note('info', 'No active non-idle wait events found for this SQL_ID right now.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            errnote('Wait guidance', SQLERRM);
    END;
    --
    ---------------------------------------------- 4.4 historical wait profile (ASH)
    h3('4.4', 'Historical Wait Profile - Last 7 Days');
    IF NOT v_awr_ok THEN
        note('info', 'AWR / ASH history is not accessible.');
    ELSE
        BEGIN
            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM dba_hist_active_sess_history WHERE sql_id = :1 AND sample_time > SYSDATE - 7'
                INTO v_total_samp USING v_sql_id;
            IF v_total_samp = 0 THEN
                note('info', 'No ASH samples for this SQL_ID in the last 7 days (the SQL may not have run, or ASH history has aged out).');
            ELSE
                q := q'[SELECT event, wait_class, samples, pct FROM (
                          SELECT NVL(event, 'CPU + Wait for CPU') AS event, NVL(wait_class, 'CPU') AS wait_class, COUNT(*) AS samples,
                                 ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct
                          FROM dba_hist_active_sess_history
                          WHERE sql_id = :1 AND sample_time > SYSDATE - 7
                          GROUP BY NVL(event, 'CPU + Wait for CPU'), NVL(wait_class, 'CPU')
                          ORDER BY COUNT(*) DESC) WHERE ROWNUM <= 10]';
                v_n := 0;
                v_cnt := 0;
                OPEN rc FOR q USING v_sql_id;
                LOOP
                    FETCH rc INTO r_ash;
                    EXIT WHEN rc%NOTFOUND;
                    IF v_cnt = 0 THEN
                        tbl_open('Wait Event|Wait Class|>Samples|>% of Total|Distribution|>Approx. DB Time');
                    END IF;
                    v_cnt := v_cnt + 1;
                    v_n := v_n + r_ash.samples;
                    p('<tr>' || td(r_ash.event) || td(r_ash.wclass, 'nw') || td(fnum(r_ash.samples), 'r')
                      || td(fdec(r_ash.pct, 1) || '%', 'r') || tdh('<div class="bar"><span style="width:' || TO_CHAR(LEAST(r_ash.pct, 100), 'FM990.0', 'NLS_NUMERIC_CHARACTERS=''.,''') || '%"></span></div>')
                      || td(fdur(r_ash.samples * 10), 'r nw') || '</tr>');
                END LOOP;
                CLOSE rc;
                IF v_total_samp > v_n THEN
                    p('<tr><td colspan="2"><i>All other events</i></td>' || td(fnum(v_total_samp - v_n), 'r')
                      || td(fdec(100 * (v_total_samp - v_n) / v_total_samp, 1) || '%', 'r') || '<td></td>'
                      || td(fdur((v_total_samp - v_n) * 10), 'r nw') || '</tr>');
                END IF;
                p('<tr style="font-weight:600"><td colspan="2">Total</td>' || td(fnum(v_total_samp), 'r') || td('100.0%', 'r') || '<td></td>'
                  || td(fdur(v_total_samp * 10), 'r nw') || '</tr>');
                tbl_close;
                p('<p class="small">Source: DBA_HIST_ACTIVE_SESS_HISTORY. AWR keeps one in every ten one-second ASH samples, so each sample represents roughly 10 seconds of active session time; "Approx. DB Time" is samples x 10. Top 10 events shown, sorted by sample count.</p>');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF rc%ISOPEN THEN CLOSE rc; END IF;
                errnote('ASH wait profile', SQLERRM);
        END;
    END IF;
    p('</div>');
    --
    --=========================================================================
    -- SECTION 5 : PLAN STABILITY CHECK  (immediately before Findings)
    --=========================================================================
    p('<div class="card" id="sec5">');
    h2('5', 'Plan Stability Check');
    --
    v_plans.DELETE;
    v_n_plans := 0;
    v_cur_idx := NULL;
    v_cur_phv := NULL;
    v_cur_src := NULL;
    v_chg_date := NULL;
    v_best := NULL;
    v_worst := NULL;
    v_first_all := NULL;
    v_last_all := NULL;
    v_awr_snaps := 0;
    --
    -- 5.0 collect every plan_hash_value seen for this SQL_ID (cache + AWR)
    BEGIN
        IF v_awr_ok THEN
            v_awr_cte := q'[a AS (SELECT h.plan_hash_value phv, COUNT(*) snaps, SUM(h.executions_delta) execs, SUM(h.elapsed_time_delta) ela,
                                         CAST(MIN(s.begin_interval_time) AS DATE) first_seen, CAST(MAX(s.end_interval_time) AS DATE) last_seen
                                  FROM dba_hist_sqlstat h JOIN dba_hist_snapshot s
                                    ON s.snap_id = h.snap_id AND s.dbid = h.dbid AND s.instance_number = h.instance_number
                                  WHERE h.sql_id = :2 GROUP BY h.plan_hash_value)]';
        ELSE
            v_awr_cte := q'[a AS (SELECT CAST(NULL AS NUMBER) phv, CAST(NULL AS NUMBER) snaps, CAST(NULL AS NUMBER) execs, CAST(NULL AS NUMBER) ela,
                                         CAST(NULL AS DATE) first_seen, CAST(NULL AS DATE) last_seen FROM dual WHERE 1 = 0 AND :2 IS NULL)]';
        END IF;
        q := q'[WITH c AS (SELECT plan_hash_value phv, SUM(executions) execs, SUM(elapsed_time) ela, MAX(last_active_time) last_active
                           FROM v$sqlstats WHERE sql_id = :1 GROUP BY plan_hash_value), ]'
             || v_awr_cte
             || q'[ SELECT NVL(c.phv, a.phv), c.execs, ROUND(c.ela / 1000000 / NULLIF(c.execs, 0), 3), c.last_active,
                           a.snaps, a.execs, ROUND(a.ela / 1000000 / NULLIF(a.execs, 0), 3), a.first_seen, a.last_seen
                    FROM c FULL OUTER JOIN a ON a.phv = c.phv
                    ORDER BY GREATEST(NVL(a.last_seen, DATE '1900-01-01'), NVL(c.last_active, DATE '1900-01-01')) DESC]';
        OPEN rc FOR q USING v_sql_id, v_sql_id;
        LOOP
            FETCH rc INTO r_plan;
            EXIT WHEN rc%NOTFOUND;
            v_n_plans := v_n_plans + 1;
            v_plans(v_n_plans) := r_plan;
        END LOOP;
        CLOSE rc;
    EXCEPTION
        WHEN OTHERS THEN
            IF rc%ISOPEN THEN CLOSE rc; END IF;
            v_plans.DELETE;
            v_n_plans := 0;
            errnote('Plan history', SQLERRM);
    END;
    --
    -- current plan = most recently active plan in the cursor cache, otherwise the latest AWR plan
    v_ts := NULL;
    FOR i IN 1 .. v_n_plans LOOP
        IF v_plans(i).c_last IS NOT NULL AND (v_ts IS NULL OR v_plans(i).c_last > v_ts) THEN
            v_ts := v_plans(i).c_last;
            v_cur_idx := i;
            v_cur_src := 'most recently active plan in the cursor cache';
        END IF;
    END LOOP;
    IF v_cur_idx IS NULL THEN
        FOR i IN 1 .. v_n_plans LOOP
            IF v_plans(i).a_last IS NOT NULL AND (v_ts IS NULL OR v_plans(i).a_last > v_ts) THEN
                v_ts := v_plans(i).a_last;
                v_cur_idx := i;
                v_cur_src := 'latest plan in AWR (cursor not in the shared pool)';
            END IF;
        END LOOP;
    END IF;
    IF v_cur_idx IS NULL AND v_n_plans > 0 THEN
        v_cur_idx := 1;
        v_cur_src := 'first plan listed (no timestamps available)';
    END IF;
    IF v_cur_idx IS NOT NULL THEN
        v_cur_phv := v_plans(v_cur_idx).phv;
        v_chg_date := v_plans(v_cur_idx).a_first;
    END IF;
    --
    -- previous plan = a different plan with the latest observation time; fastest / slowest plan; observed window
    v_ts := NULL;
    v_prev_idx := NULL;
    FOR i IN 1 .. v_n_plans LOOP
        v_awr_snaps := v_awr_snaps + NVL(v_plans(i).a_snaps, 0);
        IF i <> v_cur_idx THEN
            IF v_ts IS NULL OR GREATEST(NVL(v_plans(i).a_last, DATE '1900-01-01'), NVL(v_plans(i).c_last, DATE '1900-01-01')) > v_ts THEN
                v_ts := GREATEST(NVL(v_plans(i).a_last, DATE '1900-01-01'), NVL(v_plans(i).c_last, DATE '1900-01-01'));
                v_prev_idx := i;
            END IF;
        END IF;
        IF v_plans(i).a_first IS NOT NULL AND (v_first_all IS NULL OR v_plans(i).a_first < v_first_all) THEN v_first_all := v_plans(i).a_first; END IF;
        IF v_plans(i).a_last IS NOT NULL AND (v_last_all IS NULL OR v_plans(i).a_last > v_last_all) THEN v_last_all := v_plans(i).a_last; END IF;
        v_eff := NVL(v_plans(i).a_avg, v_plans(i).c_avg);
        IF v_eff IS NOT NULL THEN
            IF v_best IS NULL OR v_eff < v_best THEN v_best := v_eff; v_best_phv := v_plans(i).phv; END IF;
            IF v_worst IS NULL OR v_eff > v_worst THEN v_worst := v_eff; v_worst_phv := v_plans(i).phv; END IF;
        END IF;
    END LOOP;
    --
    -- signature correlation
    v_sibl_ids := 0;
    v_sibl_plans := 0;
    IF v_fms IS NOT NULL THEN
        BEGIN
            IF v_awr_ok THEN
                EXECUTE IMMEDIATE 'SELECT COUNT(DISTINCT sql_id) FROM (SELECT sql_id FROM v$sqlstats WHERE force_matching_signature = :1 UNION SELECT sql_id FROM dba_hist_sqlstat WHERE force_matching_signature = :2)'
                    INTO v_sibl_ids USING v_fms, v_fms;
                EXECUTE IMMEDIATE 'SELECT COUNT(DISTINCT phv) FROM (SELECT plan_hash_value phv FROM v$sqlstats WHERE force_matching_signature = :1 UNION SELECT plan_hash_value FROM dba_hist_sqlstat WHERE force_matching_signature = :2)'
                    INTO v_sibl_plans USING v_fms, v_fms;
            ELSE
                EXECUTE IMMEDIATE 'SELECT COUNT(DISTINCT sql_id), COUNT(DISTINCT plan_hash_value) FROM v$sqlstats WHERE force_matching_signature = :1'
                    INTO v_sibl_ids, v_sibl_plans USING v_fms;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                v_sibl_ids := 0;
                v_sibl_plans := 0;
        END;
    END IF;
    --
    -- child cursors in the cache
    v_children := 0;
    v_child_envs := 0;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*), COUNT(DISTINCT optimizer_env_hash_value) FROM v$sql WHERE sql_id = :1'
            INTO v_children, v_child_envs USING v_sql_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_children := 0;
            v_child_envs := 0;
    END;
    --
    -------------------------------------------------------------- 5.1 verdict
    h3('5.1', 'Result');
    IF v_n_plans = 0 THEN
        note('info', '<span class="verdict">' || badge('NO PLAN DATA', 'mute') || '</span> No plan hash value was found for this SQL_ID in the cursor cache or AWR, so plan stability cannot be assessed.');
    ELSIF v_n_plans = 1 THEN
        note('ok', '<span class="verdict">' || badge('STABLE PLAN', 'ok') || '</span> Only one plan hash value (<b>' || v_cur_phv
             || '</b>) has been observed for this SQL_ID in the cursor cache and the available AWR history'
             || CASE WHEN v_first_all IS NOT NULL THEN ' (' || TO_CHAR(v_first_all, 'YYYY-MM-DD HH24:MI') || ' to ' || TO_CHAR(v_last_all, 'YYYY-MM-DD HH24:MI') || ')' END
             || '. No plan change was recorded within that history.');
    ELSE
        note('warn', '<span class="verdict">' || badge('MULTIPLE PLANS / POTENTIAL PLAN INSTABILITY', 'warn') || '</span> '
             || fnum(v_n_plans) || ' different plan hash values have been observed for the same SQL_ID. The optimizer has produced different plans over time; this alone does not prove a performance problem - see the performance comparison below.');
    END IF;
    --
    -------------------------------------------------------------- 5.2 key facts
    h3('5.2', 'Key facts');
    p('<table class="kv">');
    kv('SQL_ID', '<b>' || esc(v_sql_id) || '</b>');
    kv('Current plan hash value', CASE WHEN v_cur_phv IS NULL THEN 'not available'
                                       ELSE '<b>' || v_cur_phv || '</b> <span class="small">(' || esc(v_cur_src) || ')</span>' END);
    kv('Number of different plans observed', fnum(v_n_plans));
    kv('Multiple plans for the same SQL_ID?', CASE WHEN v_n_plans > 1 THEN badge('YES', 'warn') WHEN v_n_plans = 1 THEN badge('NO', 'ok') ELSE '-' END);
    kv('Plan hash value changed?',
       CASE WHEN v_n_plans < 2 THEN CASE WHEN v_n_plans = 1 THEN badge('NO', 'ok') || ' same plan in all observed history' ELSE '-' END
            ELSE badge('YES', 'warn') || ' the current plan differs from '
                 || CASE WHEN v_prev_idx IS NOT NULL THEN 'earlier plan <b>' || v_plans(v_prev_idx).phv || '</b>' END
                 || CASE WHEN v_chg_date IS NOT NULL THEN '; current plan first seen in AWR at ' || TO_CHAR(v_chg_date, 'YYYY-MM-DD HH24:MI')
                         ELSE '; first-seen time of the current plan is not available (cursor cache only)' END
       END);
    kv('Observed in AWR (first - last snapshot interval)',
       CASE WHEN v_first_all IS NULL THEN 'no AWR history' ELSE TO_CHAR(v_first_all, 'YYYY-MM-DD HH24:MI') || ' - ' || TO_CHAR(v_last_all, 'YYYY-MM-DD HH24:MI') || ' (' || fnum(v_awr_snaps) || ' snapshot rows)' END);
    kv('Force matching signature', CASE WHEN v_fms IS NULL THEN 'not applicable' ELSE '<code>' || TO_CHAR(v_fms) || '</code>' END);
    kv('SQL_IDs sharing this signature (cache + AWR)', CASE WHEN v_fms IS NULL THEN '-' ELSE fnum(v_sibl_ids) END);
    kv('Distinct plans across all SQL_IDs with this signature', CASE WHEN v_fms IS NULL THEN '-' ELSE fnum(v_sibl_plans) END);
    kv('Child cursors in the cursor cache / distinct optimizer environments', fnum(v_children) || ' / ' || fnum(v_child_envs));
    p('</table>');
    --
    -------------------------------------------------------------- 5.3 plan table
    h3('5.3', 'Plan history and execution performance by plan');
    IF v_n_plans = 0 THEN
        note('info', 'Nothing to show.');
    ELSE
        tbl_open('>Plan Hash Value|Observed In|>Executions (AWR)|>Executions (cache)|>Avg Elapsed (s)|>Relative to Fastest Plan|First Observed (AWR)|Last Observed');
        FOR i IN 1 .. v_n_plans LOOP
            v_eff := NVL(v_plans(i).a_avg, v_plans(i).c_avg);
            v_ts := GREATEST(NVL(v_plans(i).a_last, DATE '1900-01-01'), NVL(v_plans(i).c_last, DATE '1900-01-01'));
            p('<tr>' || tdh('<b>' || v_plans(i).phv || '</b>' || CASE WHEN i = v_cur_idx THEN ' ' || badge('current', 'info') END, 'r nw')
              || td(CASE WHEN v_plans(i).c_last IS NOT NULL AND v_plans(i).a_last IS NOT NULL THEN 'Cache and AWR'
                         WHEN v_plans(i).c_last IS NOT NULL THEN 'Cache only' ELSE 'AWR only' END, 'nw')
              || td(fnum(v_plans(i).a_exec), 'r') || td(fnum(v_plans(i).c_exec), 'r') || td(fdec(v_eff, 3), 'r')
              || td(CASE WHEN v_eff IS NOT NULL AND v_best > 0 THEN fdec(v_eff / v_best, 1) || 'x' END, 'r')
              || td(CASE WHEN v_plans(i).a_first IS NOT NULL THEN TO_CHAR(v_plans(i).a_first, 'YYYY-MM-DD HH24:MI') END, 'nw')
              || td(CASE WHEN v_ts > DATE '1900-01-01' THEN TO_CHAR(v_ts, 'YYYY-MM-DD HH24:MI') END, 'nw') || '</tr>');
        END LOOP;
        tbl_close;
        p('<p class="small">Executions (AWR) = sum of per-snapshot deltas; Executions (cache) = cumulative since the cursor was loaded, so the two overlap and are not added. Avg Elapsed uses AWR when available, otherwise the cache.</p>');
    END IF;
    --
    -------------------------------------------------- 5.4 observations / correlation
    h3('5.4', 'Correlation with performance and environment');
    p('<ul>');
    -- performance
    IF v_n_plans > 1 AND v_best IS NOT NULL AND v_best > 0 THEN
        IF v_worst / v_best >= 2 THEN
            p('<li>' || badge('Performance', 'warn') || ' Average elapsed time per execution differs by <b>' || fdec(v_worst / v_best, 1)
              || 'x</b> between plan ' || v_best_phv || ' (' || fdec(v_best, 3) || ' s) and plan ' || v_worst_phv || ' (' || fdec(v_worst, 3)
              || ' s). The data does not by itself show which factor caused the difference.</li>');
        ELSE
            p('<li>' || badge('Performance', 'ok') || ' Average elapsed time per execution differs by less than 2x across the observed plans ('
              || fdec(v_best, 3) || ' s to ' || fdec(v_worst, 3) || ' s).</li>');
        END IF;
    ELSIF v_n_plans > 1 THEN
        p('<li>' || badge('Performance', 'mute') || ' Elapsed-time comparison is not possible (no completed executions recorded for the plans).</li>');
    END IF;
    -- signature
    IF v_fms IS NOT NULL AND v_sibl_ids > 1 THEN
        p('<li>' || badge('Signature', 'info') || ' ' || fnum(v_sibl_ids) || ' SQL_IDs share this FORCE_MATCHING_SIGNATURE (same statement, different literals) and together show '
          || fnum(v_sibl_plans) || ' distinct plan(s). The plan history of this SQL_ID alone may therefore understate plan variation for the statement as a whole.</li>');
    ELSIF v_fms IS NOT NULL THEN
        p('<li>' || badge('Signature', 'mute') || ' No other SQL_ID shares this signature.</li>');
    END IF;
    -- children
    IF v_children > 1 THEN
        p('<li>' || badge('Cursors', 'info') || ' ' || fnum(v_children) || ' child cursors exist, using ' || fnum(v_child_envs)
          || ' distinct optimizer environment(s)' || CASE WHEN v_child_envs > 1 THEN ' - children were created under different optimizer settings.' ELSE '.' END || '</li>');
    END IF;
    p('</ul>');
    --
    -- v1.2 : SQL_IDs that share the FORCE_MATCHING_SIGNATURE of the analysed SQL_ID
    IF v_fms IS NOT NULL AND v_sibl_ids > 1 THEN
        DECLARE
            TYPE t_sib IS RECORD (sql_id VARCHAR2(30), seen VARCHAR2(20), plans NUMBER, cexec NUMBER, aexec NUMBER,
                                  avg_ela NUMBER, last_act DATE);
            r_sib   t_sib;
            l_rc    t_rc;
            l_q     VARCHAR2(4000);
            l_a     VARCHAR2(2000);
            l_n     PLS_INTEGER := 0;
        BEGIN
            IF v_awr_ok THEN
                l_a := q'[a AS (SELECT h.sql_id, COUNT(DISTINCT h.plan_hash_value) plans, SUM(h.executions_delta) execs, SUM(h.elapsed_time_delta) ela,
                                       CAST(MAX(s.end_interval_time) AS DATE) last_seen
                                FROM dba_hist_sqlstat h JOIN dba_hist_snapshot s
                                  ON s.snap_id = h.snap_id AND s.dbid = h.dbid AND s.instance_number = h.instance_number
                                WHERE h.force_matching_signature = :2 GROUP BY h.sql_id)]';
            ELSE
                l_a := q'[a AS (SELECT CAST(NULL AS VARCHAR2(13)) sql_id, CAST(NULL AS NUMBER) plans, CAST(NULL AS NUMBER) execs, CAST(NULL AS NUMBER) ela,
                                       CAST(NULL AS DATE) last_seen FROM dual WHERE 1 = 0 AND :2 IS NULL)]';
            END IF;
            l_q := q'[SELECT * FROM (WITH c AS (SELECT sql_id, COUNT(DISTINCT plan_hash_value) plans, SUM(executions) execs, SUM(elapsed_time) ela,
                                                       MAX(last_active_time) last_active
                                                FROM v$sqlstats WHERE force_matching_signature = :1 GROUP BY sql_id), ]'
                   || l_a
                   || q'[ SELECT NVL(c.sql_id, a.sql_id),
                                 CASE WHEN c.sql_id IS NOT NULL AND a.sql_id IS NOT NULL THEN 'Cache and AWR'
                                      WHEN c.sql_id IS NOT NULL THEN 'Cache only' ELSE 'AWR only' END,
                                 GREATEST(NVL(c.plans, 0), NVL(a.plans, 0)), c.execs, a.execs,
                                 ROUND(NVL(a.ela, c.ela) / 1000000 / NULLIF(NVL(a.execs, c.execs), 0), 3),
                                 GREATEST(NVL(a.last_seen, DATE '1900-01-01'), NVL(c.last_active, DATE '1900-01-01'))
                          FROM c FULL OUTER JOIN a ON a.sql_id = c.sql_id
                          ORDER BY 7 DESC) WHERE ROWNUM <= 20]';
            p('<p><b>SQL_IDs sharing this FORCE_MATCHING_SIGNATURE</b> <code>' || TO_CHAR(v_fms) || '</code></p>');
            OPEN l_rc FOR l_q USING v_fms, v_fms;
            LOOP
                FETCH l_rc INTO r_sib;
                EXIT WHEN l_rc%NOTFOUND;
                IF l_n = 0 THEN
                    tbl_open('SQL_ID|Seen In|>Distinct Plans|>Executions (cache)|>Executions (AWR)|>Avg Elapsed (s)|Last Active');
                END IF;
                l_n := l_n + 1;
                p('<tr>' || tdh(esc(r_sib.sql_id) || CASE WHEN r_sib.sql_id = v_sql_id THEN ' ' || badge('analysed', 'info') END, 'nw')
                  || td(r_sib.seen, 'nw') || td(fnum(r_sib.plans), 'r') || td(fnum(r_sib.cexec), 'r') || td(fnum(r_sib.aexec), 'r')
                  || td(fdec(r_sib.avg_ela, 3), 'r')
                  || td(CASE WHEN r_sib.last_act > DATE '1900-01-01' THEN fts(r_sib.last_act) END, 'nw') || '</tr>');
            END LOOP;
            CLOSE l_rc;
            IF l_n > 0 THEN
                tbl_close;
                p('<p class="small">Same statement text apart from literal values. Executions (cache) are cumulative since the cursor was loaded; Executions (AWR) are the sum of snapshot deltas, so the two overlap. Avg Elapsed uses AWR when available, otherwise the cache. '
                  || CASE WHEN v_sibl_ids > 20 THEN 'Showing the 20 most recently active of ' || fnum(v_sibl_ids) || ' SQL_IDs.' ELSE fnum(v_sibl_ids) || ' SQL_IDs in total.' END || '</p>');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF l_rc%ISOPEN THEN CLOSE l_rc; END IF;
                errnote('SQL_IDs sharing the signature', SQLERRM);
        END;
    END IF;
    --
    -- child cursor details (baseline / profile / adaptive flags)
    IF v_children > 0 THEN
        BEGIN
            q := q'[SELECT * FROM (SELECT child_number, plan_hash_value, executions, ROUND(elapsed_time / 1000000 / NULLIF(executions, 0), 3),
                           optimizer_env_hash_value, is_bind_sensitive, is_bind_aware, is_reoptimizable,
                           sql_plan_baseline, sql_profile, sql_patch, parsing_schema_name
                    FROM v$sql WHERE sql_id = :1 ORDER BY child_number) WHERE ROWNUM <= 20]';
            v_cnt := 0;
            OPEN rc FOR q USING v_sql_id;
            LOOP
                FETCH rc INTO r_child;
                EXIT WHEN rc%NOTFOUND;
                IF v_cnt = 0 THEN
                    p('<p><b>Child cursors in the shared pool</b> (first 20)</p>');
                    tbl_open('>Child #|>Plan Hash Value|>Executions|>Avg Elapsed (s)|>Optimizer Env Hash|Bind Sensitive|Bind Aware|Re-optimizable|SQL Plan Baseline|SQL Profile|SQL Patch|Parsing Schema');
                END IF;
                v_cnt := v_cnt + 1;
                p('<tr>' || td(TO_CHAR(r_child.child), 'r') || td(TO_CHAR(r_child.phv), 'r nw') || td(fnum(r_child.execs), 'r')
                  || td(fdec(r_child.avg_ela, 3), 'r') || td(TO_CHAR(r_child.env_hash), 'r nw') || td(r_child.bind_sens) || td(r_child.bind_aware)
                  || td(r_child.reopt) || td(r_child.baseline) || td(r_child.profile) || td(r_child.patch) || td(r_child.schema) || '</tr>');
            END LOOP;
            CLOSE rc;
            IF v_cnt > 0 THEN
                tbl_close;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF rc%ISOPEN THEN CLOSE rc; END IF;
                errnote('Child cursor details', SQLERRM);
        END;
    --
        -- reasons for multiple children
        IF v_children > 1 THEN
            BEGIN
                EXECUTE IMMEDIATE q'[SELECT SUM(CASE WHEN optimizer_mismatch = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN optimizer_mode_mismatch = 'Y' THEN 1 ELSE 0 END),
                                            SUM(CASE WHEN outline_mismatch = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN bind_mismatch = 'Y' THEN 1 ELSE 0 END),
                                            SUM(CASE WHEN bind_equiv_failure = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN roll_invalid_mismatch = 'Y' THEN 1 ELSE 0 END)
                                     FROM v$sql_shared_cursor WHERE sql_id = :1]'
                    INTO v_ox, v_om, v_ol, v_bm, v_bq, v_rm USING v_sql_id;
                v_mism := NULL;
                IF NVL(v_ox, 0) > 0 THEN v_mism := v_mism || '<li>OPTIMIZER_MISMATCH (' || v_ox || ' child cursor(s)): optimizer parameter settings differed between sessions.</li>'; END IF;
                IF NVL(v_om, 0) > 0 THEN v_mism := v_mism || '<li>OPTIMIZER_MODE_MISMATCH (' || v_om || '): optimizer mode differed.</li>'; END IF;
                IF NVL(v_ol, 0) > 0 THEN v_mism := v_mism || '<li>OUTLINE_MISMATCH (' || v_ol || '): outline / baseline differed.</li>'; END IF;
                IF NVL(v_bm, 0) > 0 THEN v_mism := v_mism || '<li>BIND_MISMATCH (' || v_bm || '): bind variable definitions differed.</li>'; END IF;
                IF NVL(v_bq, 0) > 0 THEN v_mism := v_mism || '<li>BIND_EQUIV_FAILURE (' || v_bq || '): adaptive cursor sharing created a new child for different bind values.</li>'; END IF;
                IF NVL(v_rm, 0) > 0 THEN v_mism := v_mism || '<li>ROLL_INVALID_MISMATCH (' || v_rm || '): cursor was invalidated (for example by statistics gathering) and re-parsed.</li>'; END IF;
                IF v_mism IS NOT NULL THEN
                    p('<p><b>Recorded reasons for multiple child cursors</b> (V$SQL_SHARED_CURSOR)</p><ul>' || v_mism || '</ul>');
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    errnote('Child cursor mismatch reasons', SQLERRM);
            END;
        END IF;
    END IF;
    --
    --
    --
    ---------------------------------------------------------------------------
    -- v1.2 : RELATED TABLE / INDEX STATISTICS, FRAGMENTATION, CORRELATION
    --        Read-only. A failure inside this nested block is reported in the
    --        HTML and never stops the rest of the report.
    ---------------------------------------------------------------------------
    DECLARE
        c_min_mb      NUMBER := NVL(:b_frag_min_mb, 100);
        c_density     NUMBER := NVL(:b_frag_density, 50);
        c_ratio       NUMBER := NVL(:b_frag_ratio, 2);
        c_misest      CONSTANT NUMBER := 10;
        --
        TYPE t_obj IS RECORD (owner VARCHAR2(128), name VARCHAR2(128), otype VARCHAR2(10),
                              n_ops NUMBER, n_full NUMBER, part_acc NUMBER);
        --
        TYPE t_tr IS RECORD (owner VARCHAR2(128), name VARCHAR2(128), n_full NUMBER, part_acc NUMBER,
                             st_found BOOLEAN, status VARCHAR2(12), last_an DATE, num_rows NUMBER, blocks NUMBER,
                             avg_len NUMBER, smp NUMBER, glob VARCHAR2(3), usr VARCHAR2(3), locked VARCHAR2(10),
                             stale VARCHAR2(3), chain NUMBER,
                             d_found BOOLEAN, partitioned VARCHAR2(3), temp VARCHAR2(1), iot VARCHAR2(12), compr VARCHAR2(30),
                             p_cnt NUMBER, p_nost NUMBER, p_stale NUMBER, sp_cnt NUMBER, sp_nost NUMBER, sp_stale NUMBER,
                             seg_cnt NUMBER, seg_bytes NUMBER, seg_blocks NUMBER, seg_ext NUMBER,
                             m_est NUMBER, m_act NUMBER, m_ratio NUMBER,
                             cls VARCHAR2(16), density NUMBER, evid VARCHAR2(1000), follow VARCHAR2(1000),
                             d_cre DATE, d_ddl DATE, m_cnt NUMBER, m_ins NUMBER, m_upd NUMBER, m_del NUMBER, m_ts DATE, m_trunc NUMBER, cov BOOLEAN);
        TYPE t_tr_tab IS TABLE OF t_tr INDEX BY PLS_INTEGER;
        --
        TYPE t_ir IS RECORD (owner VARCHAR2(128), name VARCHAR2(128), n_full NUMBER, part_acc NUMBER,
                             d_found BOOLEAN, tab_owner VARCHAR2(128), tab_name VARCHAR2(128), itype VARCHAR2(30),
                             idx_status VARCHAR2(10), partitioned VARCHAR2(3), last_an DATE, num_rows NUMBER,
                             dkeys NUMBER, leaf NUMBER, cf NUMBER, blevel NUMBER, pct_free NUMBER,
                             stale VARCHAR2(3), locked VARCHAR2(10), status VARCHAR2(12),
                             p_cnt NUMBER, p_nost NUMBER, p_unus NUMBER, sp_cnt NUMBER, sp_nost NUMBER, sp_unus NUMBER,
                             seg_cnt NUMBER, seg_bytes NUMBER, seg_blocks NUMBER, seg_ext NUMBER,
                             m_est NUMBER, m_act NUMBER, m_ratio NUMBER,
                             cls VARCHAR2(16), ratio NUMBER, evid VARCHAR2(1000), follow VARCHAR2(1000));
        TYPE t_ir_tab IS TABLE OF t_ir INDEX BY PLS_INTEGER;
        --
        TYPE t_fnd IS RECORD (sev VARCHAR2(10), obj VARCHAR2(300), cond VARCHAR2(500), evid VARCHAR2(1200),
                              impact VARCHAR2(1000), act VARCHAR2(1500), valid VARCHAR2(1500));
        TYPE t_fnd_tab IS TABLE OF t_fnd INDEX BY PLS_INTEGER;
        TYPE t_smap IS TABLE OF VARCHAR2(12) INDEX BY VARCHAR2(300);
        --
        x_o           t_obj;
        x_tab         t_tr_tab;
        x_idx         t_ir_tab;
        x_tr          t_tr;
        x_ir          t_ir;
        x_f           t_fnd_tab;
        x_tmap        t_smap;
        x_rc          t_rc;
        x_nt          PLS_INTEGER := 0;
        x_ni          PLS_INTEGER := 0;
        x_nf          PLS_INTEGER := 0;
        x_src         VARCHAR2(30);
        x_pfx         VARCHAR2(3);
        x_try         VARCHAR2(3);
        x_dba_err     VARCHAR2(500);
        x_seg_err     VARCHAR2(500);
        x_seg_ok      BOOLEAN := FALSE;
        x_n           NUMBER;
        x_errs        VARCHAR2(3000);
        x_s           VARCHAR2(4000);
        x_s2          VARCHAR2(4000);
        x_key         VARCHAR2(300);
        x_unk         PLS_INTEGER := 0;
        x_c_tglob     VARCHAR2(100);
        x_c_tusr      VARCHAR2(100);
        x_c_tlock     VARCHAR2(100);
        x_c_tstale    VARCHAR2(100);
        x_c_tchain    VARCHAR2(100);
        x_c_istale    VARCHAR2(100);
        x_c_ilock     VARCHAR2(100);
        l_ot          VARCHAR2(30);
        l_c           NUMBER;
        l_n1          NUMBER;
        l_n2          NUMBER;
        x_dml         VARCHAR2(800);
        x_ops         NUMBER;
        x_d_cre       DATE;
        x_d_ddl       DATE;
        x_m_cnt       NUMBER;
        x_m_ins       NUMBER;
        x_m_upd       NUMBER;
        x_m_del       NUMBER;
        x_m_ts        DATE;
        x_m_trunc     NUMBER;
        x_rc2         t_rc;
        x_nm          VARCHAR2(300);
        x_mbs         NUMBER;
        x_dp          NUMBER;
        x_dmltxt      VARCHAR2(800);
        x_cmd         VARCHAR2(600);
        x_hrs         NUMBER;
        x_ti          PLS_INTEGER;
        x_prio        PLS_INTEGER;
        x_fid         NUMBER;
        x_fo          VARCHAR2(128);
        x_fn          VARCHAR2(128);
        x_fcard       NUMBER;
        x_fcost       NUMBER;
        x_facc        VARCHAR2(4000);
        x_ffil        VARCHAR2(4000);
        x_act         NUMBER;
        x_buf         NUMBER;
        x_stt         NUMBER;
        x_frac        NUMBER;
        x_hit         VARCHAR2(1000);
        x_nidx        PLS_INTEGER;
        x_ic1         VARCHAR2(128);
        x_ic2         VARCHAR2(128);
        x_k           PLS_INTEGER;
        x_sel         BOOLEAN;
        --
        -- ---- small helpers -------------------------------------------------
        FUNCTION col_ok(p_view IN VARCHAR2, p_col IN VARCHAR2) RETURN BOOLEAN IS
            l_x NUMBER;
        BEGIN
            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM all_tab_columns WHERE owner = ''SYS'' AND table_name = :1 AND column_name = :2'
                INTO l_x USING UPPER(p_view), UPPER(p_col);
            RETURN l_x > 0;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN FALSE;
        END col_ok;
        --
        -- column expression when the column exists in this release, otherwise a typed NULL
        FUNCTION sel(p_view IN VARCHAR2, p_col IN VARCHAR2, p_null IN VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            IF col_ok(p_view, p_col) THEN RETURN LOWER(p_col); END IF;
            RETURN p_null;
        END sel;
        --
        PROCEDURE note_err(p_what IN VARCHAR2, p_err IN VARCHAR2) IS
        BEGIN
            IF NVL(LENGTH(x_errs), 0) < 2400 THEN
                x_errs := x_errs || '<li>' || esc(p_what) || ': <code>' || esc(SUBSTR(p_err, 1, 200)) || '</code></li>';
            END IF;
        END note_err;
        --
        FUNCTION stat_status(p_found IN BOOLEAN, p_last IN DATE, p_stale IN VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            IF NOT NVL(p_found, FALSE) THEN RETURN 'UNKNOWN'; END IF;
            IF p_last IS NULL THEN RETURN 'MISSING'; END IF;
            IF p_stale = 'YES' THEN RETURN 'STALE'; END IF;
            IF p_stale = 'NO' THEN RETURN 'NOT STALE'; END IF;
            RETURN 'UNKNOWN';
        END stat_status;
        --
        FUNCTION stat_badge(p_s IN VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            RETURN badge(p_s, CASE p_s WHEN 'STALE' THEN 'warn' WHEN 'NOT STALE' THEN 'ok' WHEN 'MISSING' THEN 'bad' ELSE 'mute' END);
        END stat_badge;
        --
        FUNCTION cls_badge(p_s IN VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            RETURN CASE p_s
                       WHEN 'HIGH'           THEN badge('HIGH / POSSIBLE SPACE INEFFICIENCY', 'bad')
                       WHEN 'MODERATE'       THEN badge('MODERATE / REVIEW REQUIRED', 'warn')
                       WHEN 'LOW'            THEN badge('LOW / NO SIGNIFICANT ISSUE IDENTIFIED', 'ok')
                       WHEN 'NOT APPLICABLE' THEN badge('NOT APPLICABLE', 'mute')
                       ELSE badge('NOT ASSESSED', 'mute')
                   END;
        END cls_badge;
        --
        FUNCTION mb(p_bytes IN NUMBER) RETURN VARCHAR2 IS
        BEGIN
            IF p_bytes IS NULL THEN RETURN '-'; END IF;
            RETURN fdec(p_bytes / 1048576, 1);
        END mb;
        --
        FUNCTION method_txt(p_glob IN VARCHAR2, p_usr IN VARCHAR2, p_lock IN VARCHAR2, p_smp IN NUMBER, p_rows IN NUMBER) RETURN VARCHAR2 IS
            l_o VARCHAR2(500);
        BEGIN
            IF p_glob = 'YES' THEN
                l_o := 'GLOBAL_STATS=YES (gathered at this level)';
            ELSIF p_glob = 'NO' THEN
                l_o := 'GLOBAL_STATS=NO (aggregated from partitions, or ANALYZE-based)';
            END IF;
            IF p_usr = 'YES' THEN
                l_o := l_o || CASE WHEN l_o IS NOT NULL THEN '; ' END || 'USER_STATS=YES (set manually, not gathered)';
            END IF;
            IF p_smp IS NOT NULL AND p_rows > 0 THEN
                l_o := l_o || CASE WHEN l_o IS NOT NULL THEN '; ' END || fdec(LEAST(100, 100 * p_smp / p_rows), 1) || '% of rows sampled';
            END IF;
            IF p_lock IS NOT NULL THEN
                l_o := l_o || CASE WHEN l_o IS NOT NULL THEN '; ' END || 'locked (' || p_lock || ')';
            END IF;
            RETURN l_o;
        END method_txt;
        --
        PROCEDURE add_f(p_sev IN VARCHAR2, p_obj IN VARCHAR2, p_cond IN VARCHAR2, p_evid IN VARCHAR2,
                        p_impact IN VARCHAR2, p_act IN VARCHAR2, p_valid IN VARCHAR2) IS
        BEGIN
            x_nf := x_nf + 1;
            x_f(x_nf).sev    := p_sev;
            x_f(x_nf).obj    := SUBSTR(p_obj, 1, 300);
            x_f(x_nf).cond   := SUBSTR(p_cond, 1, 500);
            x_f(x_nf).evid   := SUBSTR(p_evid, 1, 1200);
            x_f(x_nf).impact := SUBSTR(p_impact, 1, 1000);
            x_f(x_nf).act    := SUBSTR(p_act, 1, 1500);
            x_f(x_nf).valid  := SUBSTR(p_valid, 1, 1500);
        END add_f;
        --
        FUNCTION tab_assess(r IN t_tr) RETURN VARCHAR2 IS
            l_o VARCHAR2(1800);
        BEGIN
            IF r.status = 'STALE' THEN
                l_o := 'Oracle flags these statistics as stale (STALE_STATS = YES). Optimizer estimates may not reflect current data; staleness alone does not prove a performance problem.';
            ELSIF r.status = 'NOT STALE' THEN
                l_o := 'Not flagged stale by Oracle (last analysed ' || TRUNC(SYSDATE - r.last_an) || ' day(s) ago; age alone is not a defect).';
            ELSIF r.status = 'MISSING' THEN
                l_o := 'No statistics have been gathered (LAST_ANALYZED is NULL).'
                       || CASE WHEN r.temp = 'Y' THEN ' This is a temporary table, where missing statistics can be normal.'
                               ELSE ' The optimizer falls back to dynamic sampling or defaults.' END;
            ELSIF NOT NVL(r.st_found, FALSE) THEN
                l_o := 'No statistics record is visible to this user (object not in the dictionary view, or insufficient privileges).';
            ELSE
                l_o := 'STALE_STATS is not populated, so freshness cannot be determined (for example no DML-monitoring information has been recorded yet).';
            END IF;
            IF NVL(r.p_cnt, 0) > 0 THEN
                l_o := l_o || ' Partitions: ' || fnum(r.p_cnt) || ' (' || fnum(r.p_nost) || ' without statistics, ' || fnum(r.p_stale) || ' flagged stale).';
            END IF;
            IF NVL(r.sp_cnt, 0) > 0 THEN
                l_o := l_o || ' Subpartitions: ' || fnum(r.sp_cnt) || ' (' || fnum(r.sp_nost) || ' without statistics, ' || fnum(r.sp_stale) || ' flagged stale).';
            END IF;
            IF r.locked IS NOT NULL THEN
                l_o := l_o || ' Statistics are locked, so a normal gather skips them.';
            END IF;
            RETURN SUBSTR(l_o, 1, 1800);
        END tab_assess;
        --
        FUNCTION idx_assess(r IN t_ir) RETURN VARCHAR2 IS
            l_o VARCHAR2(1800);
            l_k VARCHAR2(300) := r.tab_owner || '.' || r.tab_name;
        BEGIN
            IF r.itype IN ('LOB', 'DOMAIN') THEN
                l_o := 'Index type ' || r.itype || ': optimizer statistics are not assessed by this report.';
            ELSIF r.status = 'STALE' THEN
                l_o := 'Oracle flags these index statistics as stale (STALE_STATS = YES). Staleness is not an index-structure problem; a rebuild does not refresh statistics.';
            ELSIF r.status = 'NOT STALE' THEN
                l_o := 'Not flagged stale by Oracle (last analysed ' || TRUNC(SYSDATE - r.last_an) || ' day(s) ago; age alone is not a defect).';
            ELSIF r.status = 'MISSING' THEN
                l_o := 'No index statistics have been gathered (LAST_ANALYZED is NULL).';
            ELSIF NOT NVL(r.d_found, FALSE) THEN
                l_o := 'No index record is visible to this user (object not in the dictionary view, or insufficient privileges).';
            ELSE
                l_o := 'STALE_STATS is not populated for this index (common for indexes), so freshness is not determined from the index itself.';
                IF r.tab_owner IS NOT NULL AND x_tmap.EXISTS(l_k) THEN
                    l_o := l_o || ' The indexed table is reported as ' || x_tmap(l_k) || '.';
                END IF;
            END IF;
            IF NVL(r.p_cnt, 0) > 0 THEN
                l_o := l_o || ' Partitions: ' || fnum(r.p_cnt) || ' (' || fnum(r.p_nost) || ' without statistics).';
            END IF;
            IF NVL(r.sp_cnt, 0) > 0 THEN
                l_o := l_o || ' Subpartitions: ' || fnum(r.sp_cnt) || ' (' || fnum(r.sp_nost) || ' without statistics).';
            END IF;
            IF r.locked IS NOT NULL THEN
                l_o := l_o || ' Statistics are locked, so a normal gather skips them.';
            END IF;
            RETURN SUBSTR(l_o, 1, 1800);
        END idx_assess;
        --
        -- ---- data collection per table ------------------------------------
        PROCEDURE load_tab(p_i IN PLS_INTEGER) IS
            r    t_tr := x_tab(p_i);
            l_bs NUMBER;
            l_mb NUMBER;
        BEGIN
            r.p_cnt := 0; r.p_nost := 0; r.p_stale := 0; r.sp_cnt := 0; r.sp_nost := 0; r.sp_stale := 0;
            -- (1) table-level statistics
            BEGIN
                EXECUTE IMMEDIATE 'SELECT num_rows, blocks, avg_row_len, sample_size, last_analyzed, ' || x_c_tglob || ', ' || x_c_tusr || ', '
                    || x_c_tlock || ', ' || x_c_tstale || ', ' || x_c_tchain || ' FROM ' || x_pfx
                    || '_tab_statistics WHERE owner = :1 AND table_name = :2 AND object_type = ''TABLE'''
                    INTO r.num_rows, r.blocks, r.avg_len, r.smp, r.last_an, r.glob, r.usr, r.locked, r.stale, r.chain
                    USING r.owner, r.name;
                r.st_found := TRUE;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    r.st_found := FALSE;
                WHEN OTHERS THEN
                    r.st_found := FALSE;
                    note_err('Table statistics of ' || r.owner || '.' || r.name, SQLERRM);
            END;
            r.status := stat_status(r.st_found, r.last_an, r.stale);
            -- (2) table properties
            BEGIN
                EXECUTE IMMEDIATE 'SELECT partitioned, temporary, iot_type, compression FROM ' || x_pfx || '_tables WHERE owner = :1 AND table_name = :2'
                    INTO r.partitioned, r.temp, r.iot, r.compr USING r.owner, r.name;
                r.d_found := TRUE;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    r.d_found := FALSE;
                WHEN OTHERS THEN
                    r.d_found := FALSE;
                    note_err('Table properties of ' || r.owner || '.' || r.name, SQLERRM);
            END;
            -- (3) partition / subpartition statistics
            IF r.partitioned = 'YES' THEN
                BEGIN
                    OPEN x_rc FOR 'SELECT object_type, COUNT(*), NVL(SUM(CASE WHEN last_analyzed IS NULL THEN 1 ELSE 0 END), 0), '
                        || 'NVL(SUM(CASE WHEN ' || x_c_tstale || ' = ''YES'' THEN 1 ELSE 0 END), 0) FROM ' || x_pfx
                        || '_tab_statistics WHERE owner = :1 AND table_name = :2 AND object_type IN (''PARTITION'', ''SUBPARTITION'') GROUP BY object_type'
                        USING r.owner, r.name;
                    LOOP
                        FETCH x_rc INTO l_ot, l_c, l_n1, l_n2;
                        EXIT WHEN x_rc%NOTFOUND;
                        IF l_ot = 'PARTITION' THEN
                            r.p_cnt := l_c; r.p_nost := l_n1; r.p_stale := l_n2;
                        ELSE
                            r.sp_cnt := l_c; r.sp_nost := l_n1; r.sp_stale := l_n2;
                        END IF;
                    END LOOP;
                    CLOSE x_rc;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF x_rc%ISOPEN THEN CLOSE x_rc; END IF;
                        note_err('Partition statistics of ' || r.owner || '.' || r.name, SQLERRM);
                END;
            END IF;
            -- (4) segment size
            IF x_seg_ok THEN
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT COUNT(*), SUM(bytes), SUM(blocks), SUM(extents) FROM dba_segments WHERE owner = :1 AND segment_name = :2 AND segment_type LIKE ''TABLE%'''
                        INTO r.seg_cnt, r.seg_bytes, r.seg_blocks, r.seg_ext USING r.owner, r.name;
                EXCEPTION
                    WHEN OTHERS THEN
                        r.seg_cnt := NULL;
                        note_err('Segment size of ' || r.owner || '.' || r.name, SQLERRM);
                END;
            END IF;
            -- (5) estimated versus actual rows (needs row-source statistics)
            IF x_src = 'v$sql_plan' THEN
                BEGIN
                    EXECUTE IMMEDIATE q'[SELECT est, act FROM (SELECT cardinality est, last_output_rows / last_starts act
                                         FROM v$sql_plan_statistics_all
                                         WHERE sql_id = :1 AND plan_hash_value = :2 AND object_owner = :3 AND object_name = :4
                                           AND last_starts > 0 AND last_output_rows IS NOT NULL AND cardinality IS NOT NULL
                                         ORDER BY GREATEST(cardinality, last_output_rows / last_starts, 1)
                                                  / GREATEST(LEAST(cardinality, last_output_rows / last_starts), 1) DESC)
                                         WHERE ROWNUM = 1]'
                        INTO r.m_est, r.m_act USING v_sql_id, v_cur_phv, r.owner, r.name;
                    r.m_ratio := GREATEST(r.m_est, r.m_act, 1) / GREATEST(LEAST(r.m_est, r.m_act), 1);
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        NULL;
                    WHEN OTHERS THEN
                        note_err('Estimated/actual rows of ' || r.owner || '.' || r.name, SQLERRM);
                END;
            END IF;
            -- (6) space assessment (statistics based; no segment analysis is run)
            l_bs := CASE WHEN NVL(r.seg_blocks, 0) > 0 THEN r.seg_bytes / r.seg_blocks END;
            l_mb := r.seg_bytes / 1048576;
            IF NVL(r.blocks, 0) > 0 AND r.num_rows IS NOT NULL AND r.avg_len IS NOT NULL AND l_bs IS NOT NULL THEN
                r.density := ROUND(100 * r.num_rows * r.avg_len / (r.blocks * l_bs), 1);
            END IF;
            IF NOT x_seg_ok THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'DBA_SEGMENTS is not readable by this user.';
            ELSIF r.seg_cnt IS NULL THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'The segment lookup failed (see the messages below the tables).';
            ELSIF r.seg_cnt = 0 THEN
                IF r.temp = 'Y' THEN
                    r.cls := 'NOT APPLICABLE';
                    r.evid := 'Temporary table: no permanent segment.';
                ELSIF r.iot IS NOT NULL THEN
                    r.cls := 'NOT APPLICABLE';
                    r.evid := 'Index-organized table: the data lives in the primary-key index segment; see the index assessment.';
                ELSE
                    r.cls := 'NOT ASSESSED';
                    r.evid := 'No segment found (deferred segment creation, object not visible to this user, or object dropped).';
                END IF;
            ELSIF NOT NVL(r.st_found, FALSE) OR r.status = 'MISSING' OR r.num_rows IS NULL OR r.blocks IS NULL OR r.avg_len IS NULL THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'Table statistics are missing or incomplete, so block density cannot be estimated.';
            ELSIF r.compr = 'ENABLED' THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'Compressed table: a row-length based density estimate is not reliable.';
            ELSIF r.status = 'STALE' THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'Statistics are flagged stale, so the density estimate (' || fdec(r.density, 1) || '%) is not reliable until they are refreshed.';
            ELSIF l_mb < c_min_mb THEN
                r.cls := 'LOW';
                r.evid := 'Segment is below the review size of ' || fnum(c_min_mb) || ' MB; estimated block density ' || fdec(r.density, 1) || '%.';
            ELSIF r.density IS NOT NULL AND r.density < c_density THEN
                r.cls := 'MODERATE';
                r.evid := 'Estimated block density ' || fdec(r.density, 1) || '% (NUM_ROWS x AVG_ROW_LEN against BLOCKS in statistics) is below the review threshold of '
                          || fnum(c_density) || '%. This is an indicator, not a measurement.';
            ELSE
                r.cls := 'LOW';
                r.evid := 'Estimated block density ' || fdec(r.density, 1) || '% (threshold ' || fnum(c_density) || '%).';
            END IF;
            IF NVL(r.chain, 0) > 0 THEN
                r.evid := SUBSTR(r.evid || ' CHAIN_CNT = ' || fnum(r.chain) || ' (chained/migrated rows; a separate issue from space density).', 1, 1000);
            END IF;
            r.follow := CASE r.cls
                            WHEN 'MODERATE' THEN 'Measure before acting: DBMS_SPACE.SPACE_USAGE (ASSM segments; reads bitmap blocks, low impact) or the Segment Advisor (needs the Diagnostics/Tuning Pack licence). Consider SHRINK SPACE or MOVE only if the measurement confirms free space and change control allows it.'
                            WHEN 'LOW' THEN 'No follow-up indicated by this report.'
                            WHEN 'NOT APPLICABLE' THEN 'None for this object type.'
                            ELSE 'Resolve the reason shown, then re-run the report.'
                        END;
            -- (7) last DDL (DBA_OBJECTS) and DML counters (DBA_TAB_MODIFICATIONS)
            BEGIN
                EXECUTE IMMEDIATE 'SELECT MIN(created), MAX(last_ddl_time) FROM ' || x_pfx
                    || '_objects WHERE owner = :1 AND object_name = :2 AND object_type LIKE ''TABLE%'''
                    INTO r.d_cre, r.d_ddl USING r.owner, r.name;
            EXCEPTION
                WHEN OTHERS THEN
                    note_err('Last DDL time of ' || r.owner || '.' || r.name, SQLERRM);
            END;
            r.m_cnt := 0; r.m_trunc := 0;
            BEGIN
                -- table-level row first; for partitioned tables fall back to the partition rows
                EXECUTE IMMEDIATE 'SELECT COUNT(*), SUM(inserts), SUM(updates), SUM(deletes), MAX(timestamp), MAX(CASE WHEN truncated = ''YES'' THEN 1 ELSE 0 END) FROM '
                    || x_pfx || '_tab_modifications WHERE table_owner = :1 AND table_name = :2 AND partition_name IS NULL AND subpartition_name IS NULL'
                    INTO r.m_cnt, r.m_ins, r.m_upd, r.m_del, r.m_ts, r.m_trunc USING r.owner, r.name;
                IF r.m_cnt = 0 THEN
                    EXECUTE IMMEDIATE 'SELECT COUNT(*), SUM(inserts), SUM(updates), SUM(deletes), MAX(timestamp), MAX(CASE WHEN truncated = ''YES'' THEN 1 ELSE 0 END) FROM '
                        || x_pfx || '_tab_modifications WHERE table_owner = :1 AND table_name = :2 AND partition_name IS NOT NULL AND subpartition_name IS NULL'
                        INTO r.m_cnt, r.m_ins, r.m_upd, r.m_del, r.m_ts, r.m_trunc USING r.owner, r.name;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    r.m_cnt := NULL;
                    note_err('DML modification data of ' || r.owner || '.' || r.name, SQLERRM);
            END;
            x_tab(p_i) := r;
        END load_tab;
        --
        -- ---- data collection per index ------------------------------------
        PROCEDURE load_idx(p_i IN PLS_INTEGER) IS
            r  t_ir := x_idx(p_i);
            l_mb NUMBER;
        BEGIN
            r.p_cnt := 0; r.p_nost := 0; r.p_unus := 0; r.sp_cnt := 0; r.sp_nost := 0; r.sp_unus := 0;
            -- (1) index dictionary row and index-level statistics
            BEGIN
                EXECUTE IMMEDIATE 'SELECT table_owner, table_name, index_type, status, partitioned, last_analyzed, num_rows, distinct_keys, leaf_blocks, clustering_factor, blevel, pct_free FROM '
                    || x_pfx || '_indexes WHERE owner = :1 AND index_name = :2'
                    INTO r.tab_owner, r.tab_name, r.itype, r.idx_status, r.partitioned, r.last_an, r.num_rows, r.dkeys, r.leaf, r.cf, r.blevel, r.pct_free
                    USING r.owner, r.name;
                r.d_found := TRUE;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    r.d_found := FALSE;
                WHEN OTHERS THEN
                    r.d_found := FALSE;
                    note_err('Index properties of ' || r.owner || '.' || r.name, SQLERRM);
            END;
            -- (2) STALE_STATS / lock state from the statistics view
            BEGIN
                EXECUTE IMMEDIATE 'SELECT ' || x_c_istale || ', ' || x_c_ilock || ' FROM ' || x_pfx
                    || '_ind_statistics WHERE owner = :1 AND index_name = :2 AND object_type = ''INDEX'''
                    INTO r.stale, r.locked USING r.owner, r.name;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    NULL;
                WHEN OTHERS THEN
                    note_err('Index statistics view for ' || r.owner || '.' || r.name, SQLERRM);
            END;
            r.status := CASE WHEN r.itype IN ('LOB', 'DOMAIN') THEN 'UNKNOWN' ELSE stat_status(r.d_found, r.last_an, r.stale) END;
            -- (3) partitions of a partitioned index
            IF r.partitioned = 'YES' THEN
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT COUNT(*), NVL(SUM(CASE WHEN last_analyzed IS NULL THEN 1 ELSE 0 END), 0), NVL(SUM(CASE WHEN status = ''UNUSABLE'' THEN 1 ELSE 0 END), 0) FROM '
                        || x_pfx || '_ind_partitions WHERE index_owner = :1 AND index_name = :2'
                        INTO r.p_cnt, r.p_nost, r.p_unus USING r.owner, r.name;
                EXCEPTION
                    WHEN OTHERS THEN
                        note_err('Index partitions of ' || r.owner || '.' || r.name, SQLERRM);
                END;
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT COUNT(*), NVL(SUM(CASE WHEN last_analyzed IS NULL THEN 1 ELSE 0 END), 0), NVL(SUM(CASE WHEN status = ''UNUSABLE'' THEN 1 ELSE 0 END), 0) FROM '
                        || x_pfx || '_ind_subpartitions WHERE index_owner = :1 AND index_name = :2'
                        INTO r.sp_cnt, r.sp_nost, r.sp_unus USING r.owner, r.name;
                EXCEPTION
                    WHEN OTHERS THEN
                        note_err('Index subpartitions of ' || r.owner || '.' || r.name, SQLERRM);
                END;
            END IF;
            -- (4) segment size
            IF x_seg_ok THEN
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT COUNT(*), SUM(bytes), SUM(blocks), SUM(extents) FROM dba_segments WHERE owner = :1 AND segment_name = :2 AND segment_type LIKE ''INDEX%'''
                        INTO r.seg_cnt, r.seg_bytes, r.seg_blocks, r.seg_ext USING r.owner, r.name;
                EXCEPTION
                    WHEN OTHERS THEN
                        r.seg_cnt := NULL;
                        note_err('Segment size of ' || r.owner || '.' || r.name, SQLERRM);
                END;
            END IF;
            -- (5) estimated versus actual rows
            IF x_src = 'v$sql_plan' THEN
                BEGIN
                    EXECUTE IMMEDIATE q'[SELECT est, act FROM (SELECT cardinality est, last_output_rows / last_starts act
                                         FROM v$sql_plan_statistics_all
                                         WHERE sql_id = :1 AND plan_hash_value = :2 AND object_owner = :3 AND object_name = :4
                                           AND last_starts > 0 AND last_output_rows IS NOT NULL AND cardinality IS NOT NULL
                                         ORDER BY GREATEST(cardinality, last_output_rows / last_starts, 1)
                                                  / GREATEST(LEAST(cardinality, last_output_rows / last_starts), 1) DESC)
                                         WHERE ROWNUM = 1]'
                        INTO r.m_est, r.m_act USING v_sql_id, v_cur_phv, r.owner, r.name;
                    r.m_ratio := GREATEST(r.m_est, r.m_act, 1) / GREATEST(LEAST(r.m_est, r.m_act), 1);
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        NULL;
                    WHEN OTHERS THEN
                        note_err('Estimated/actual rows of ' || r.owner || '.' || r.name, SQLERRM);
                END;
            END IF;
            -- (6) space assessment (statistics based; no VALIDATE STRUCTURE is run)
            l_mb := r.seg_bytes / 1048576;
            IF NVL(r.leaf, 0) > 0 AND NVL(r.seg_blocks, 0) > 0 THEN
                r.ratio := ROUND(r.seg_blocks / r.leaf, 2);
            END IF;
            IF NOT x_seg_ok THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'DBA_SEGMENTS is not readable by this user.';
            ELSIF r.seg_cnt IS NULL THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'The segment lookup failed (see the messages below the tables).';
            ELSIF r.itype IN ('LOB', 'DOMAIN', 'CLUSTER') THEN
                r.cls := 'NOT APPLICABLE';
                r.evid := 'Leaf-block statistics do not apply to index type ' || r.itype || '.';
            ELSIF r.seg_cnt = 0 THEN
                r.cls := 'NOT ASSESSED';
                r.evid := CASE WHEN r.idx_status = 'UNUSABLE' OR NVL(r.p_unus, 0) > 0 OR NVL(r.sp_unus, 0) > 0
                               THEN 'No segment allocated; the index (or some of its partitions) is UNUSABLE.'
                               ELSE 'No segment found (deferred segment creation, object not visible to this user, or object dropped).' END;
            ELSIF NOT NVL(r.d_found, FALSE) OR r.status = 'MISSING' OR r.leaf IS NULL THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'Index statistics are missing or incomplete, so leaf blocks cannot be compared with the allocation.';
            ELSIF r.status = 'STALE' THEN
                r.cls := 'NOT ASSESSED';
                r.evid := 'Statistics are flagged stale; the comparison of allocated blocks with leaf blocks is not reliable until they are refreshed.';
            ELSIF l_mb < c_min_mb THEN
                r.cls := 'LOW';
                r.evid := 'Segment is below the review size of ' || fnum(c_min_mb) || ' MB; allocated blocks are ' || fdec(r.ratio, 2) || ' x leaf blocks.';
            ELSIF r.ratio IS NOT NULL AND r.ratio > c_ratio THEN
                r.cls := 'MODERATE';
                r.evid := 'Allocated blocks are ' || fdec(r.ratio, 2) || ' x the leaf blocks in statistics (review threshold ' || fdec(c_ratio, 2)
                          || ' x). Free or empty blocks may exist; pre-allocated extents also raise this ratio.';
            ELSE
                r.cls := 'LOW';
                r.evid := 'Allocated blocks are ' || fdec(r.ratio, 2) || ' x leaf blocks (threshold ' || fdec(c_ratio, 2) || ' x).';
            END IF;
            r.follow := CASE r.cls
                            WHEN 'MODERATE' THEN 'Confirm with ANALYZE INDEX ' || r.owner || '.' || r.name || ' VALIDATE STRUCTURE during a quiet window (the offline form blocks DML on the table while it runs and fills INDEX_STATS for that session), or DBMS_SPACE / the Segment Advisor. Consider SHRINK SPACE or REBUILD only if leaf-block utilisation is confirmed to be poor.'
                            WHEN 'LOW' THEN 'No follow-up indicated. Sparsely filled leaf blocks cannot be seen from this ratio; VALIDATE STRUCTURE measures leaf utilisation if that is a concern.'
                            WHEN 'NOT APPLICABLE' THEN 'None for this index type.'
                            ELSE 'Resolve the reason shown, then re-run the report.'
                        END;
            x_idx(p_i) := r;
        END load_idx;
    --
    BEGIN
        IF v_is_plsql THEN
            note('info', 'This SQL_ID is an anonymous PL/SQL block, so it references no tables or indexes itself. Analyse the SQL statements it executes (see section 6).');
        ELSIF v_cur_phv IS NULL THEN
            note('info', 'No execution plan is available for this SQL_ID (not in the cursor cache and not in AWR), so its tables and indexes cannot be identified. This says nothing about the state of statistics or fragmentation.');
        ELSE
            ---------------------------------------------------- identify objects
            x_src := NULL;
            BEGIN
                IF cnt('v$sql_plan', 'object_name IS NOT NULL') > 0 THEN
                    x_src := 'v$sql_plan';
                ELSIF v_awr_ok THEN
                    IF cnt('dba_hist_sql_plan', 'object_name IS NOT NULL') > 0 THEN
                        x_src := 'dba_hist_sql_plan';
                    END IF;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    x_src := NULL;
                    errnote('Plan object lookup', SQLERRM);
            END;
            IF x_src IS NULL THEN
                note('info', 'The plan steps with object names are not available in V$SQL_PLAN or DBA_HIST_SQL_PLAN, so the related tables and indexes cannot be identified. An empty list here is not evidence that the statement uses no tables.');
            ELSE
                BEGIN
                    OPEN x_rc FOR 'SELECT object_owner, object_name, CASE WHEN object_type LIKE ''INDEX%'' THEN ''INDEX'' ELSE ''TABLE'' END, '
                        || 'COUNT(DISTINCT id), COUNT(DISTINCT CASE WHEN operation = ''TABLE ACCESS'' AND options LIKE ''%FULL%'' THEN id END), '
                        || 'MAX(CASE WHEN partition_start IS NOT NULL THEN 1 ELSE 0 END) FROM ' || x_src
                        || ' WHERE sql_id = :1 AND plan_hash_value = :2 AND object_name IS NOT NULL AND object_owner IS NOT NULL'
                        || ' AND (object_type LIKE ''INDEX%'' OR object_type LIKE ''TABLE%'')'
                        || ' GROUP BY object_owner, object_name, CASE WHEN object_type LIKE ''INDEX%'' THEN ''INDEX'' ELSE ''TABLE'' END'
                        || ' ORDER BY 3 DESC, 1, 2'
                        USING v_sql_id, v_cur_phv;
                    LOOP
                        FETCH x_rc INTO x_o;
                        EXIT WHEN x_rc%NOTFOUND;
                        IF x_o.otype = 'TABLE' THEN
                            x_nt := x_nt + 1;
                            x_tab(x_nt) := x_tr;
                            x_tab(x_nt).owner := x_o.owner; x_tab(x_nt).name := x_o.name;
                            x_tab(x_nt).n_full := x_o.n_full; x_tab(x_nt).part_acc := x_o.part_acc;
                        ELSE
                            x_ni := x_ni + 1;
                            x_idx(x_ni) := x_ir;
                            x_idx(x_ni).owner := x_o.owner; x_idx(x_ni).name := x_o.name;
                            x_idx(x_ni).n_full := x_o.n_ops; x_idx(x_ni).part_acc := x_o.part_acc;
                        END IF;
                    END LOOP;
                    CLOSE x_rc;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF x_rc%ISOPEN THEN CLOSE x_rc; END IF;
                        x_nt := 0; x_ni := 0;
                        errnote('Plan object lookup', SQLERRM);
                END;
                IF x_nt + x_ni = 0 THEN
                    note('info', 'The plan (' || CASE x_src WHEN 'v$sql_plan' THEN 'cursor cache' ELSE 'AWR' END
                                 || ') was read, but it contains no table or index references that could be listed. If the lookup above reported an error, the list is incomplete rather than empty.');
                ELSE
                    ------------------------------------------------ dictionary access
                    x_pfx := NULL;
                    FOR k IN 1 .. 2 LOOP
                        EXIT WHEN x_pfx IS NOT NULL;
                        x_try := CASE k WHEN 1 THEN 'DBA' ELSE 'ALL' END;
                        BEGIN
                            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || x_try || '_tab_statistics WHERE 1 = 0' INTO x_n;
                            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || x_try || '_ind_statistics WHERE 1 = 0' INTO x_n;
                            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || x_try || '_tables WHERE 1 = 0' INTO x_n;
                            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || x_try || '_indexes WHERE 1 = 0' INTO x_n;
                            x_pfx := x_try;
                        EXCEPTION
                            WHEN OTHERS THEN
                                IF k = 1 THEN x_dba_err := SQLERRM; ELSE x_s2 := SQLERRM; END IF;
                        END;
                    END LOOP;
                    IF x_pfx IS NULL THEN
                        note('warn', 'Related objects were identified (' || fnum(x_nt) || ' table(s), ' || fnum(x_ni) || ' index(es)) but their statistics cannot be read: neither the DBA_* nor the ALL_* statistics views are accessible (<code>'
                                     || esc(SUBSTR(x_dba_err, 1, 200)) || '</code>). Grant SELECT on DBA_TAB_STATISTICS, DBA_IND_STATISTICS, DBA_TABLES and DBA_INDEXES directly to this user.');
                        p('<ul>');
                        FOR i IN 1 .. x_nt LOOP
                            p('<li>Table <code>' || esc(x_tab(i).owner) || '.' || esc(x_tab(i).name) || '</code></li>');
                        END LOOP;
                        FOR i IN 1 .. x_ni LOOP
                            p('<li>Index <code>' || esc(x_idx(i).owner) || '.' || esc(x_idx(i).name) || '</code></li>');
                        END LOOP;
                        p('</ul>');
                    ELSE
                        IF x_pfx = 'ALL' THEN
                            note('warn', 'DBA_* dictionary views are not readable (<code>' || esc(SUBSTR(x_dba_err, 1, 200))
                                         || '</code>); ALL_* views are used instead. ALL_* views show only objects this user can access, so objects owned by other schemas may appear as UNKNOWN.');
                        END IF;
                        BEGIN
                            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM dba_segments WHERE 1 = 0' INTO x_n;
                            x_seg_ok := TRUE;
                        EXCEPTION
                            WHEN OTHERS THEN
                                x_seg_ok := FALSE;
                                x_seg_err := SQLERRM;
                        END;
                        -- optional columns, checked against the dictionary of this release
                        x_c_tglob  := sel(x_pfx || '_TAB_STATISTICS', 'GLOBAL_STATS',     'CAST(NULL AS VARCHAR2(3))');
                        x_c_tusr   := sel(x_pfx || '_TAB_STATISTICS', 'USER_STATS',       'CAST(NULL AS VARCHAR2(3))');
                        x_c_tlock  := sel(x_pfx || '_TAB_STATISTICS', 'STATTYPE_LOCKED',  'CAST(NULL AS VARCHAR2(5))');
                        x_c_tstale := sel(x_pfx || '_TAB_STATISTICS', 'STALE_STATS',      'CAST(NULL AS VARCHAR2(3))');
                        x_c_tchain := sel(x_pfx || '_TAB_STATISTICS', 'CHAIN_CNT',        'TO_NUMBER(NULL)');
                        x_c_istale := sel(x_pfx || '_IND_STATISTICS', 'STALE_STATS',      'CAST(NULL AS VARCHAR2(3))');
                        x_c_ilock  := sel(x_pfx || '_IND_STATISTICS', 'STATTYPE_LOCKED',  'CAST(NULL AS VARCHAR2(5))');
                        ------------------------------------------------ collect
                        FOR i IN 1 .. x_nt LOOP
                            load_tab(i);
                            x_tmap(x_tab(i).owner || '.' || x_tab(i).name) := x_tab(i).status;
                        END LOOP;
                        FOR i IN 1 .. x_ni LOOP
                            load_idx(i);
                        END LOOP;
                        --
                        ------------------------------------------------ Related Table Statistics
                        p('<p><b>Related Table Statistics</b></p>');
                        IF x_nt = 0 THEN
                            note('info', 'The plan references no tables directly (index-only access, or only views / other objects).');
                        ELSE
                            tbl_open('Table Owner|Table Name|Last Analyzed|Statistics Status|>NUM_ROWS|>BLOCKS|>SAMPLE_SIZE');
                            FOR i IN 1 .. x_nt LOOP
                                p('<tr>' || td(x_tab(i).owner) || td(x_tab(i).name) || td(fts(x_tab(i).last_an), 'nw')
                                  || tdh(stat_badge(x_tab(i).status), 'nw') || td(fnum(x_tab(i).num_rows), 'r') || td(fnum(x_tab(i).blocks), 'r')
                                  || td(fnum(x_tab(i).smp), 'r') || '</tr>');
                                IF x_tab(i).status IN ('UNKNOWN', 'MISSING') THEN x_unk := x_unk + 1; END IF;
                            END LOOP;
                            tbl_close;
                        END IF;
                        --
                        ------------------------------------------------ Related Index Statistics
                        p('<p><b>Related Index Statistics</b></p>');
                        IF x_ni = 0 THEN
                            note('info', 'The plan references no indexes (all access is by full scan or by other object types).');
                        ELSE
                            tbl_open('Index Owner|Index Name|Table Owner|Table Name|Index Type|Last Analyzed|Statistics Status|Status / Validity|>NUM_ROWS|>DISTINCT_KEYS|>LEAF_BLOCKS');
                            FOR i IN 1 .. x_ni LOOP
                                x_s := CASE
                                           WHEN NVL(x_idx(i).p_unus, 0) + NVL(x_idx(i).sp_unus, 0) > 0
                                               THEN badge('UNUSABLE', 'bad') || '<br><span class="small">' || fnum(NVL(x_idx(i).p_unus, 0) + NVL(x_idx(i).sp_unus, 0)) || ' partition(s) unusable</span>'
                                           WHEN x_idx(i).idx_status = 'UNUSABLE' THEN badge('UNUSABLE', 'bad')
                                           WHEN x_idx(i).idx_status = 'VALID'    THEN badge('VALID', 'ok')
                                           WHEN x_idx(i).idx_status = 'N/A'      THEN badge('N/A (partitioned)', 'mute') || '<br><span class="small">' || fnum(x_idx(i).p_cnt) || ' partition(s), none unusable</span>'
                                           ELSE badge(NVL(x_idx(i).idx_status, 'UNKNOWN'), 'mute')
                                       END;
                                p('<tr>' || td(x_idx(i).owner) || td(x_idx(i).name) || td(x_idx(i).tab_owner) || td(x_idx(i).tab_name) || td(x_idx(i).itype)
                                  || td(fts(x_idx(i).last_an), 'nw') || tdh(stat_badge(x_idx(i).status), 'nw') || tdh(x_s, 'nw')
                                  || td(fnum(x_idx(i).num_rows), 'r') || td(fnum(x_idx(i).dkeys), 'r') || td(fnum(x_idx(i).leaf), 'r') || '</tr>');
                                IF x_idx(i).status IN ('UNKNOWN', 'MISSING') THEN x_unk := x_unk + 1; END IF;
                            END LOOP;
                            tbl_close;
                        END IF;
                        --
                        ------------------------------------------------ Fragmentation
                        p('<p><b>Related Table and Index Fragmentation Analysis</b></p>');
                        IF NOT x_seg_ok THEN
                            note('info', 'Objects were identified, but segment sizes are not available: DBA_SEGMENTS is not readable (<code>' || esc(SUBSTR(x_seg_err, 1, 200))
                                         || '</code>). Fragmentation is shown as NOT ASSESSED; grant SELECT on DBA_SEGMENTS directly to this user.');
                        END IF;
                        p('<p class="small"><b>Related tables</b></p>');
                        IF x_nt = 0 THEN
                            note('info', 'No related tables to assess.');
                        ELSE
                            tbl_open('Table|Type / Partitioning|>Segment (MB)|>Allocated Blocks|>Extents|>BLOCKS in Statistics|>Wasted Space %|Assessment and Evidence');
                            FOR i IN 1 .. x_nt LOOP
                                x_s := CASE WHEN NOT NVL(x_tab(i).d_found, FALSE) THEN 'Unknown (properties not visible)'
                                            WHEN x_tab(i).temp = 'Y' THEN 'Temporary table'
                                            WHEN x_tab(i).iot IS NOT NULL THEN 'Index-organized table'
                                            WHEN x_tab(i).partitioned = 'YES' THEN 'Partitioned heap table (' || fnum(x_tab(i).p_cnt) || ' partitions'
                                                 || CASE WHEN NVL(x_tab(i).sp_cnt, 0) > 0 THEN ', ' || fnum(x_tab(i).sp_cnt) || ' subpartitions' END || ')'
                                            ELSE 'Heap table' END
                                       || CASE WHEN x_tab(i).part_acc = 1 THEN '; partition access in plan' END;
                                p('<tr>' || td(x_tab(i).owner || '.' || x_tab(i).name) || td(x_s)
                                  || td(mb(x_tab(i).seg_bytes), 'r') || td(fnum(x_tab(i).seg_blocks), 'r') || td(fnum(x_tab(i).seg_ext), 'r')
                                  || td(fnum(x_tab(i).blocks), 'r') || td(CASE WHEN x_tab(i).density IS NOT NULL THEN fdec(GREATEST(0, 100 - x_tab(i).density), 1) || '%' END, 'r')
                                  || tdh(cls_badge(x_tab(i).cls) || '<br><span class="small">' || esc(x_tab(i).evid) || '</span>') || '</tr>');
                            END LOOP;
                            tbl_close;
                        END IF;
                        p('<p class="small"><b>Related indexes</b></p>');
                        IF x_ni = 0 THEN
                            note('info', 'No related indexes to assess.');
                        ELSE
                            tbl_open('Index|Table|Index Type|>Segment (MB)|>Allocated Blocks|>Extents|>Wasted Space %|>Leaf Block Level (BLEVEL)|Assessment and Evidence');
                            FOR i IN 1 .. x_ni LOOP
                                p('<tr>' || td(x_idx(i).owner || '.' || x_idx(i).name) || td(CASE WHEN x_idx(i).tab_name IS NOT NULL THEN x_idx(i).tab_owner || '.' || x_idx(i).tab_name END)
                                  || td(x_idx(i).itype) || td(mb(x_idx(i).seg_bytes), 'r') || td(fnum(x_idx(i).seg_blocks), 'r') || td(fnum(x_idx(i).seg_ext), 'r')
                                  || td(CASE WHEN x_idx(i).ratio IS NOT NULL THEN fdec(GREATEST(0, 100 * (1 - 1 / x_idx(i).ratio)), 1) || '%' END, 'r')
                                  || td(fnum(x_idx(i).blevel), 'r')
                                  || tdh(cls_badge(x_idx(i).cls) || '<br><span class="small">' || esc(x_idx(i).evid) || '</span>') || '</tr>');
                            END LOOP;
                            tbl_close;
                        END IF;
                        --
                        --
                        ------------------------------------------------ Last DDL / DML
                        p('<p><b>Last DDL and DML Information</b></p>');
                        IF x_nt = 0 THEN
                            note('info', 'The plan references no tables directly, so there is no DDL/DML information to report.');
                        ELSE
                            tbl_open('Table Owner|Table Name|Created|Last DDL Time|>Days Since Last DDL|Last DML Recorded|>INSERTS|>UPDATES|>DELETES|Flags');
                            FOR i IN 1 .. x_nt LOOP
                                x_s := NULL;
                                IF x_tab(i).d_ddl >= SYSDATE - 7 THEN
                                    x_s := badge('DDL in last 7 days', 'warn');
                                END IF;
                                IF NVL(x_tab(i).m_trunc, 0) = 1 THEN
                                    x_s := x_s || CASE WHEN x_s IS NOT NULL THEN ' ' END || badge('Truncated since statistics', 'warn');
                                END IF;
                                IF x_tab(i).m_cnt = 0 THEN
                                    x_s := x_s || CASE WHEN x_s IS NOT NULL THEN ' ' END || '<span class="small">no DML recorded</span>';
                                ELSIF x_tab(i).m_cnt IS NULL THEN
                                    x_s := x_s || CASE WHEN x_s IS NOT NULL THEN ' ' END || '<span class="small">DML data unavailable</span>';
                                END IF;
                                p('<tr>' || td(x_tab(i).owner) || td(x_tab(i).name) || td(fts(x_tab(i).d_cre), 'nw') || td(fts(x_tab(i).d_ddl), 'nw')
                                  || td(CASE WHEN x_tab(i).d_ddl IS NOT NULL THEN fnum(TRUNC(SYSDATE - x_tab(i).d_ddl)) END, 'r')
                                  || td(fts(x_tab(i).m_ts), 'nw') || td(fnum(x_tab(i).m_ins), 'r') || td(fnum(x_tab(i).m_upd), 'r') || td(fnum(x_tab(i).m_del), 'r')
                                  || tdh(x_s) || '</tr>');
                            END LOOP;
                            tbl_close;
                        END IF;
                        --
                        ------------------------------------------------ v1.2 : findings drawn from these objects (shown in section 6)
                        BEGIN
                            FOR i IN 1 .. x_nt LOOP
                                x_nm  := x_tab(i).owner || '.' || x_tab(i).name;
                                x_mbs := x_tab(i).seg_bytes / 1048576;
                                x_dp  := CASE WHEN NVL(x_tab(i).num_rows, 0) > 0 AND NVL(x_tab(i).m_cnt, 0) > 0
                                              THEN ROUND(100 * (NVL(x_tab(i).m_ins, 0) + NVL(x_tab(i).m_upd, 0) + NVL(x_tab(i).m_del, 0)) / x_tab(i).num_rows, 1) END;
                                x_dmltxt := CASE WHEN NVL(x_tab(i).m_cnt, 0) > 0
                                                 THEN fnum(x_tab(i).m_ins) || ' inserts, ' || fnum(x_tab(i).m_upd) || ' updates and ' || fnum(x_tab(i).m_del)
                                                      || ' deletes are recorded since the statistics were gathered (' || fdec(x_dp, 1) || '% of NUM_ROWS; counters last flushed '
                                                      || fts(x_tab(i).m_ts) || ')'
                                                 WHEN x_tab(i).m_cnt = 0 THEN 'no DML is recorded in DBA_TAB_MODIFICATIONS since the statistics were gathered'
                                                 ELSE 'DML counters could not be read' END;
                                x_cmd := 'EXEC DBMS_STATS.GATHER_TABLE_STATS(ownname => ''' || x_tab(i).owner || ''', tabname => ''' || x_tab(i).name || ''', cascade => TRUE);';
                                --
                                IF x_tab(i).status = 'STALE' THEN
                                    fd_add(CASE WHEN NVL(x_tab(i).n_full, 0) > 0 OR NVL(x_tab(i).m_ratio, 0) >= c_misest THEN 1 ELSE 2 END,
                                        'Stale optimizer statistics on ' || x_nm,
                                        'Oracle flags the statistics as stale (STALE_STATS = YES). They were gathered ' || fts(x_tab(i).last_an) || ' when NUM_ROWS was '
                                          || fnum(x_tab(i).num_rows) || '; ' || x_dmltxt || '.'
                                          || CASE WHEN NVL(x_tab(i).n_full, 0) > 0 THEN ' The plan reads this table with ' || fnum(x_tab(i).n_full) || ' full-scan step(s).' END
                                          || CASE WHEN NVL(x_tab(i).m_ratio, 0) >= c_misest
                                                  THEN ' The row estimate on this table is ' || fdec(x_tab(i).m_ratio, 1) || 'x off (estimated ' || fnum(x_tab(i).m_est)
                                                       || ', actual ' || fnum(x_tab(i).m_act) || ' per start).' END
                                          || CASE WHEN x_tab(i).locked IS NOT NULL THEN ' The statistics are LOCKED (' || x_tab(i).locked || '), so the scheduled gather skips this table.' END,
                                        CASE WHEN x_tab(i).locked IS NOT NULL
                                             THEN 'Decide first why the statistics were locked; if it was not deliberate: EXEC DBMS_STATS.UNLOCK_TABLE_STATS(''' || x_tab(i).owner || ''', ''' || x_tab(i).name || '''); then ' END
                                          || x_cmd || ' Export the current statistics first (DBMS_STATS.EXPORT_TABLE_STATS) so the change can be reverted, and run it off-peak: dependent cursors are invalidated and may be re-optimised.',
                                        'DBA_TAB_STATISTICS.STALE_STATS must read NO afterwards. Compare the plan hash value and the elapsed time per execution before and after (sections 3 and 5).');
                                ELSIF x_tab(i).status = 'MISSING' AND NVL(x_tab(i).temp, 'N') <> 'Y' THEN
                                    fd_add(1, 'No optimizer statistics on ' || x_nm,
                                        'LAST_ANALYZED is NULL, so the optimizer uses dynamic sampling or built-in defaults for this table' || CASE WHEN x_mbs IS NOT NULL THEN ' (segment ' || mb(x_tab(i).seg_bytes) || ' MB)' END
                                          || '; ' || x_dmltxt || '.' || CASE WHEN NVL(x_tab(i).n_full, 0) > 0 THEN ' The plan reads it with ' || fnum(x_tab(i).n_full) || ' full-scan step(s).' END,
                                        x_cmd || ' If the table is loaded and emptied by a batch job, gather right after the load instead.',
                                        'LAST_ANALYZED is populated and the cardinality estimates in the plan (section 1.6, E-Rows against A-Rows) move closer to the actual rows.');
                                ELSIF NVL(x_tab(i).p_nost, 0) + NVL(x_tab(i).sp_nost, 0) > 0 THEN
                                    fd_add(2, fnum(NVL(x_tab(i).p_nost, 0) + NVL(x_tab(i).sp_nost, 0)) || ' partition(s) of ' || x_nm || ' have no statistics',
                                        'Of ' || fnum(x_tab(i).p_cnt) || ' partition(s)' || CASE WHEN NVL(x_tab(i).sp_cnt, 0) > 0 THEN ' and ' || fnum(x_tab(i).sp_cnt) || ' subpartition(s)' END
                                          || ', ' || fnum(NVL(x_tab(i).p_nost, 0)) || ' partition(s) and ' || fnum(NVL(x_tab(i).sp_nost, 0)) || ' subpartition(s) have LAST_ANALYZED = NULL.'
                                          || CASE WHEN x_tab(i).part_acc = 1 THEN ' The plan prunes partitions, so a missing partition-level figure directly affects the estimate.' END,
                                        x_cmd || ' (granularity AUTO gathers the missing partitions; for large partitioned tables consider INCREMENTAL statistics).',
                                        'DBA_TAB_STATISTICS shows LAST_ANALYZED for every partition of ' || x_nm || '.');
                                END IF;
                                --
                                IF x_tab(i).locked IS NOT NULL AND x_tab(i).status <> 'STALE' AND NVL(x_dp, 0) >= 10 THEN
                                    fd_add(2, 'Locked statistics on ' || x_nm || ' while the data keeps changing',
                                        'Statistics are locked (' || x_tab(i).locked || ') and ' || x_dmltxt || '.',
                                        'Confirm the lock is intended. If it is not: EXEC DBMS_STATS.UNLOCK_TABLE_STATS(''' || x_tab(i).owner || ''', ''' || x_tab(i).name || '''); then ' || x_cmd,
                                        'STATTYPE_LOCKED is NULL and the nightly gather job refreshes the table.');
                                END IF;
                                --
                                IF NVL(x_tab(i).m_ratio, 0) >= c_misest AND x_tab(i).status NOT IN ('STALE', 'MISSING') THEN
                                    fd_add(CASE WHEN x_tab(i).m_ratio >= 100 THEN 1 ELSE 2 END,
                                        'Row estimate off by ' || fdec(x_tab(i).m_ratio, 0) || 'x on ' || x_nm,
                                        'The worst plan step on this table was estimated at ' || fnum(x_tab(i).m_est) || ' row(s) per start but returned ' || fnum(x_tab(i).m_act)
                                          || ' in the last execution, although the statistics are not flagged stale (' || x_tab(i).status || ', gathered ' || fts(x_tab(i).last_an) || ').',
                                        'Stale-flag statistics are not the cause here, so look at skew and correlation: check DBA_TAB_COL_STATISTICS.HISTOGRAM for the columns in the predicates of this step (plan section 1.6) and, '
                                          || 'where two or more columns are filtered together, create a column group: SELECT DBMS_STATS.CREATE_EXTENDED_STATS(''' || x_tab(i).owner || ''', ''' || x_tab(i).name
                                          || ''', ''(COL1,COL2)'') FROM dual; then regather. Only then consider a SQL Plan Baseline.',
                                        'E-Rows and A-Rows of this step agree within 10x in the next execution (needs STATISTICS_LEVEL = ALL or the GATHER_PLAN_STATISTICS hint).');
                                END IF;
                                --
                                IF x_tab(i).d_ddl IS NOT NULL AND x_tab(i).d_ddl >= SYSDATE - 7 THEN
                                    x_hrs := CASE WHEN v_chg_date IS NOT NULL THEN ROUND(ABS(v_chg_date - x_tab(i).d_ddl) * 24, 1) END;
                                    fd_add(2, 'Recent DDL on ' || x_nm,
                                        'LAST_DDL_TIME is ' || fts(x_tab(i).d_ddl) || ' (' || fdec(SYSDATE - x_tab(i).d_ddl, 1) || ' day(s) ago); the table was created ' || fts(x_tab(i).d_cre) || '.'
                                          || CASE WHEN v_chg_date IS NOT NULL
                                                  THEN ' The analysed plan ' || v_cur_phv || ' was first seen in AWR at ' || fts(v_chg_date) || ', ' || fdec(x_hrs, 1) || ' hour(s) '
                                                       || CASE WHEN v_chg_date >= x_tab(i).d_ddl THEN 'after' ELSE 'before' END || ' the DDL'
                                                       || CASE WHEN x_hrs <= 24 THEN ', so the two are probably related.' ELSE ', so a direct link is not established.' END
                                             END,
                                        'Find out which change was made (ALTER TABLE, index created or dropped, partition operation, TRUNCATE) and whether it was planned. DDL invalidates the dependent cursors, which then re-parse; if elapsed time worsened after ' || fts(x_tab(i).d_ddl)
                                          || ', compare with the trend in section 3 and, if needed, restore the previous behaviour or pin the earlier plan with a SQL Plan Baseline.',
                                        'The plan hash value and elapsed time per execution after this timestamp are stable and match the earlier values.');
                                END IF;
                                --
                                IF NVL(x_tab(i).m_trunc, 0) = 1 THEN
                                    fd_add(2, x_nm || ' was truncated since its statistics were gathered',
                                        'DBA_TAB_MODIFICATIONS marks the table as truncated (TRUNCATED = YES) after the statistics were taken at ' || fts(x_tab(i).last_an)
                                          || '; the statistics (NUM_ROWS = ' || fnum(x_tab(i).num_rows) || ') describe data that is no longer there.',
                                        x_cmd,
                                        'NUM_ROWS in DBA_TAB_STATISTICS matches a current COUNT(*) of the table within a few per cent.');
                                END IF;
                                --
                                IF NVL(x_tab(i).num_rows, 0) > 0 AND NVL(x_tab(i).chain, 0) * 10 >= x_tab(i).num_rows THEN
                                    fd_add(2, 'Chained or migrated rows on ' || x_nm,
                                        'CHAIN_CNT = ' || fnum(x_tab(i).chain) || ' against NUM_ROWS = ' || fnum(x_tab(i).num_rows) || ' (' || fdec(100 * x_tab(i).chain / x_tab(i).num_rows, 1)
                                          || '%). Each chained row costs an additional block read when it is fetched.',
                                        'Identify the rows with ANALYZE TABLE ... LIST CHAINED ROWS (writes to a CHAINED_ROWS table; run in a controlled window), raise PCTFREE for tables that are updated after insert, then reorganise with ALTER TABLE ... MOVE ONLINE (19c) and rebuild the indexes only if the move leaves them UNUSABLE. CHAIN_CNT is populated only by ANALYZE, so confirm the figure before acting.',
                                        'The "table fetch continued row" statistic of the session falls for this SQL after the reorganisation.');
                                END IF;
                                --
                                IF x_tab(i).cls = 'MODERATE' THEN
                                    fd_add(3, 'Possible space inefficiency in ' || x_nm,
                                        x_tab(i).evid || ' Segment ' || mb(x_tab(i).seg_bytes) || ' MB.',
                                        x_tab(i).follow,
                                        'DBMS_SPACE.SPACE_USAGE reports the share of blocks that are mostly empty; only a measured figure justifies a reorganisation.');
                                END IF;
                            END LOOP;
                            --
                            FOR i IN 1 .. x_ni LOOP
                                x_nm := x_idx(i).owner || '.' || x_idx(i).name;
                                x_ti := NULL;
                                FOR j IN 1 .. x_nt LOOP
                                    IF x_tab(j).owner = x_idx(i).tab_owner AND x_tab(j).name = x_idx(i).tab_name THEN
                                        x_ti := j;
                                        EXIT;
                                    END IF;
                                END LOOP;
                                --
                                IF x_idx(i).idx_status = 'UNUSABLE' OR NVL(x_idx(i).p_unus, 0) + NVL(x_idx(i).sp_unus, 0) > 0 THEN
                                    fd_add(1, 'Index ' || x_nm || ' is UNUSABLE',
                                        CASE WHEN x_idx(i).idx_status = 'UNUSABLE' THEN 'The index on ' || x_idx(i).tab_owner || '.' || x_idx(i).tab_name || ' has STATUS = UNUSABLE.'
                                             ELSE fnum(NVL(x_idx(i).p_unus, 0) + NVL(x_idx(i).sp_unus, 0)) || ' of its ' || fnum(NVL(x_idx(i).p_cnt, 0)) || ' partition(s) are UNUSABLE.' END
                                          || ' With SKIP_UNUSABLE_INDEXES = TRUE (the default) the optimizer silently ignores it, so this SQL falls back to another access path, and DML on the table may fail if the index is unique. The analysed plan uses it, which means it was usable when that plan was captured.',
                                        'Find the cause (a MOVE, SPLIT or partition maintenance without UPDATE INDEXES), then ALTER INDEX ' || x_nm || ' REBUILD'
                                          || CASE WHEN x_idx(i).partitioned = 'YES' THEN ' PARTITION <name> for each unusable partition (query DBA_IND_PARTITIONS WHERE STATUS = ''UNUSABLE'')' END || ' ONLINE;',
                                        'STATUS = VALID in DBA_INDEXES / DBA_IND_PARTITIONS, and the plan again contains the index.');
                                ELSIF x_idx(i).status = 'MISSING' THEN
                                    fd_add(2, 'No statistics on index ' || x_nm,
                                        'LAST_ANALYZED is NULL for this index of ' || x_idx(i).tab_owner || '.' || x_idx(i).tab_name || '; the optimizer cannot cost access through it correctly.',
                                        'EXEC DBMS_STATS.GATHER_INDEX_STATS(ownname => ''' || x_idx(i).owner || ''', indname => ''' || x_idx(i).name || ''');  (or gather the table with cascade => TRUE)',
                                        'DBA_INDEXES.LAST_ANALYZED is populated; LEAF_BLOCKS and CLUSTERING_FACTOR are filled.');
                                END IF;
                                --
                                IF x_ti IS NOT NULL AND x_idx(i).last_an IS NOT NULL AND x_tab(x_ti).last_an IS NOT NULL
                                   AND NVL(x_idx(i).num_rows, 0) > 0 AND NVL(x_tab(x_ti).num_rows, 0) > 0
                                   AND ABS(x_idx(i).last_an - x_tab(x_ti).last_an) > 1
                                   AND GREATEST(x_idx(i).num_rows, x_tab(x_ti).num_rows) >= 2 * LEAST(x_idx(i).num_rows, x_tab(x_ti).num_rows) THEN
                                    fd_add(2, 'Index and table statistics disagree: ' || x_nm,
                                        'Index NUM_ROWS = ' || fnum(x_idx(i).num_rows) || ' (gathered ' || fts(x_idx(i).last_an) || ') but table ' || x_tab(x_ti).owner || '.' || x_tab(x_ti).name
                                          || ' NUM_ROWS = ' || fnum(x_tab(x_ti).num_rows) || ' (gathered ' || fts(x_tab(x_ti).last_an) || '). The statistics come from different points in time. '
                                          || '(An index on nullable columns can legitimately hold fewer entries than the table has rows.)',
                                        'Regather together so table, column and index figures are consistent: EXEC DBMS_STATS.GATHER_TABLE_STATS(ownname => ''' || x_tab(x_ti).owner || ''', tabname => ''' || x_tab(x_ti).name || ''', cascade => TRUE);',
                                        'Index and table NUM_ROWS are within a few per cent of each other (allowing for NULL keys).');
                                END IF;
                                --
                                IF x_ti IS NOT NULL AND NVL(x_tab(x_ti).num_rows, 0) >= 100000 AND NVL(x_tab(x_ti).blocks, 0) > 0
                                   AND x_idx(i).cf IS NOT NULL AND x_idx(i).cf >= 0.5 * x_tab(x_ti).num_rows THEN
                                    fd_add(3, 'Poor clustering factor on index ' || x_nm,
                                        'CLUSTERING_FACTOR = ' || fnum(x_idx(i).cf) || ' against ' || fnum(x_tab(x_ti).num_rows) || ' rows in ' || fnum(x_tab(x_ti).blocks)
                                          || ' table blocks (' || fdec(100 * x_idx(i).cf / x_tab(x_ti).num_rows, 0) || '% of NUM_ROWS). Consecutive index entries point to different table blocks, so a range scan returning N rows can need close to N table-block visits.',
                                        'This is a property of how the table data is ordered, not a fault of the index. For queries that read large ranges through it, a full scan or another access path may be cheaper; a covering index avoids the table visits. Rebuilding the index does not change the clustering factor.',
                                        'Compare buffer gets per execution (section 6.1) with the rows returned; a ratio near one block per row confirms the effect.');
                                END IF;
                                --
                                IF x_idx(i).cls = 'MODERATE' THEN
                                    fd_add(3, 'Possible index space inefficiency in ' || x_nm,
                                        x_idx(i).evid || ' Segment ' || mb(x_idx(i).seg_bytes) || ' MB.',
                                        x_idx(i).follow,
                                        'ANALYZE INDEX ... VALIDATE STRUCTURE (quiet window) or DBMS_SPACE gives a measured leaf-block utilisation; rebuild only if it is poor.');
                                END IF;
                            END LOOP;
                            --
                            ------------------------------------------ full table scans: predicate, selectivity, candidate indexes
                            x_k := 0;
                            OPEN x_rc FOR 'SELECT id, object_owner, object_name, MAX(cardinality), MAX(cost), MAX(access_predicates), MAX(filter_predicates) FROM ' || x_src
                                || ' WHERE sql_id = :1 AND plan_hash_value = :2 AND operation = ''TABLE ACCESS'' AND options LIKE ''%FULL%'' AND object_name IS NOT NULL'
                                || ' GROUP BY id, object_owner, object_name ORDER BY MAX(cost) DESC NULLS LAST'
                                USING v_sql_id, v_cur_phv;
                            LOOP
                                FETCH x_rc INTO x_fid, x_fo, x_fn, x_fcard, x_fcost, x_facc, x_ffil;
                                EXIT WHEN x_rc%NOTFOUND OR x_k >= 5;
                                x_k  := x_k + 1;
                                v_fd_full := TRUE;
                                x_nm := x_fo || '.' || x_fn;
                                x_ti := NULL;
                                FOR j IN 1 .. x_nt LOOP
                                    IF x_tab(j).owner = x_fo AND x_tab(j).name = x_fn THEN
                                        x_ti := j;
                                        EXIT;
                                    END IF;
                                END LOOP;
                                x_mbs := CASE WHEN x_ti IS NOT NULL THEN x_tab(x_ti).seg_bytes / 1048576 END;
                                x_frac := CASE WHEN x_ti IS NOT NULL AND NVL(x_tab(x_ti).num_rows, 0) > 0 AND x_fcard IS NOT NULL
                                               THEN ROUND(100 * x_fcard / x_tab(x_ti).num_rows, 2) END;
                                -- actual figures of the last execution (needs row-source statistics)
                                x_act := NULL; x_buf := NULL; x_stt := NULL;
                                IF x_src = 'v$sql_plan' THEN
                                    BEGIN
                                        EXECUTE IMMEDIATE 'SELECT MAX(last_output_rows), MAX(NVL(last_cr_buffer_gets, 0) + NVL(last_cu_buffer_gets, 0)), MAX(last_starts) FROM v$sql_plan_statistics_all'
                                            || ' WHERE sql_id = :1 AND plan_hash_value = :2 AND id = :3 AND last_starts > 0'
                                            INTO x_act, x_buf, x_stt USING v_sql_id, v_cur_phv, x_fid;
                                    EXCEPTION
                                        WHEN OTHERS THEN
                                            x_act := NULL; x_buf := NULL; x_stt := NULL;
                                    END;
                                END IF;
                                -- indexes of this table whose leading column is mentioned in the predicate
                                x_hit := NULL; x_nidx := 0;
                                BEGIN
                                    OPEN x_rc2 FOR 'SELECT index_name, column_name FROM ' || x_pfx || '_ind_columns WHERE table_owner = :1 AND table_name = :2 AND column_position = 1 ORDER BY index_name'
                                        USING x_fo, x_fn;
                                    LOOP
                                        FETCH x_rc2 INTO x_ic1, x_ic2;
                                        EXIT WHEN x_rc2%NOTFOUND;
                                        x_nidx := x_nidx + 1;
                                        IF INSTR(x_ffil || ' ' || x_facc, '"' || x_ic2 || '"') > 0 AND NVL(LENGTH(x_hit), 0) < 700 THEN
                                            x_hit := x_hit || CASE WHEN x_hit IS NOT NULL THEN ', ' END || x_ic1 || ' (leading column ' || x_ic2 || ')';
                                        END IF;
                                    END LOOP;
                                    CLOSE x_rc2;
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        IF x_rc2%ISOPEN THEN CLOSE x_rc2; END IF;
                                        x_nidx := -1;
                                        note_err('Index columns of ' || x_nm, SQLERRM);
                                END;
                                x_sel := (x_act IS NOT NULL AND x_ti IS NOT NULL AND NVL(x_tab(x_ti).num_rows, 0) > 0 AND x_act * 100 < x_tab(x_ti).num_rows)
                                         OR (x_act IS NULL AND x_frac IS NOT NULL AND x_frac < 1);
                                x_prio := CASE WHEN x_sel AND (NVL(x_buf, 0) >= 100000 OR NVL(x_mbs, 0) >= c_min_mb) THEN 1
                                               WHEN NVL(x_buf, 0) >= 100000 OR NVL(x_mbs, 0) >= c_min_mb THEN 2
                                               ELSE 3 END;
                                IF x_ffil IS NULL AND x_facc IS NULL THEN
                                    fd_add(x_prio, 'Full scan of ' || x_nm || ' (plan step ' || x_fid || ') without a predicate',
                                        'Step ' || x_fid || ' reads every row of the table' || CASE WHEN x_mbs IS NOT NULL THEN ' (segment ' || mb(x_tab(x_ti).seg_bytes) || ' MB)' END
                                          || CASE WHEN x_buf IS NOT NULL THEN '; the last execution used ' || fnum(x_buf) || ' buffer gets and returned ' || fnum(x_act) || ' row(s)' END || '.',
                                        'Check whether the statement really needs the whole table (an aggregate or reporting query might). If it is a lookup, a join condition or WHERE clause is missing or was lost in a view.',
                                        'Compare the rows returned with the rows the business question needs.');
                                ELSIF INSTR(x_ffil || x_facc, 'INTERNAL_FUNCTION') > 0 THEN
                                    fd_add(LEAST(x_prio, 2), 'Possible implicit data type conversion on a full scan of ' || x_nm,
                                        'The predicate of step ' || x_fid || ' contains INTERNAL_FUNCTION, which Oracle adds when it converts a column implicitly; a converted column cannot use a normal index. Predicate: '
                                          || SUBSTR(NVL(x_ffil, x_facc), 1, 400)
                                          || CASE WHEN x_buf IS NOT NULL THEN ' The last execution used ' || fnum(x_buf) || ' buffer gets for ' || fnum(x_act) || ' row(s).' END,
                                        'Make the compared types match: bind or compare the column in its own data type (for example a NUMBER column against a number bind, a DATE column against a DATE rather than a string). Fix the application or the bind type; do not add a function-based index first.',
                                        'The predicate in section 1.6 no longer shows INTERNAL_FUNCTION and the step becomes an index access.');
                                ELSIF x_hit IS NOT NULL THEN
                                    fd_add(x_prio, 'Full scan of ' || x_nm || ' although an index matches its predicate',
                                        'Step ' || x_fid || ' filter: ' || SUBSTR(NVL(x_ffil, x_facc), 1, 400) || '. Index ' || x_hit || ' exists, yet the optimizer chose a full scan'
                                          || CASE WHEN x_fcost IS NOT NULL THEN ' (scan cost ' || fnum(x_fcost) || ')' END
                                          || CASE WHEN x_frac IS NOT NULL THEN '. It expects to keep ' || fdec(x_frac, 2) || '% of ' || fnum(x_tab(x_ti).num_rows) || ' rows' END
                                          || CASE WHEN x_act IS NOT NULL THEN '. The last execution returned ' || fnum(x_act) || ' row(s) using ' || fnum(x_buf) || ' buffer gets' END || '.',
                                        CASE WHEN x_sel THEN 'The predicate is selective, so the full scan is probably the wrong choice. Check for a function or expression on the indexed column, an implicit conversion, and a skewed column without a histogram; compare the plan with an INDEX hint (/*+ INDEX(' || x_fn || ') */) in a test session before changing anything permanent.'
                                             ELSE 'Much of the table qualifies, so the full scan may well be the cheaper path; verify with the plan using an INDEX hint in a test session before treating this as a problem.' END,
                                        'Elapsed time and buffer gets of this step with and without the index.');
                                ELSE
                                    fd_add(x_prio, 'Full scan of ' || x_nm || ' with no index on the filtered column',
                                        'Step ' || x_fid || ' filter: ' || SUBSTR(NVL(x_ffil, x_facc), 1, 400) || '. '
                                          || CASE WHEN x_nidx > 0 THEN 'None of the ' || fnum(x_nidx) || ' index(es) on the table leads with a column used in this predicate.'
                                                  WHEN x_nidx = 0 THEN 'The table has no index.' ELSE 'The indexes of the table could not be read.' END
                                          || CASE WHEN x_mbs IS NOT NULL THEN ' Segment ' || mb(x_tab(x_ti).seg_bytes) || ' MB.' END
                                          || CASE WHEN x_frac IS NOT NULL THEN ' The optimizer expects ' || fdec(x_frac, 2) || '% of the rows to qualify.' END
                                          || CASE WHEN x_act IS NOT NULL THEN ' The last execution returned ' || fnum(x_act) || ' row(s) using ' || fnum(x_buf) || ' buffer gets.' END,
                                        CASE WHEN x_sel THEN 'The predicate keeps few rows, so an index on the filtered column(s) is a candidate: evaluate it on a test system (and check the write overhead on ' || x_nm || ') before creating it.'
                                             ELSE 'The predicate keeps a large share of the rows, so an index would probably not help; reducing the volume read (partitioning, compression, or a narrower query) matters more.' END,
                                        'Compare the plan, buffer gets and elapsed time with a test index in place.');
                                END IF;
                            END LOOP;
                            CLOSE x_rc;
                        EXCEPTION
                            WHEN OTHERS THEN
                                IF x_rc%ISOPEN THEN CLOSE x_rc; END IF;
                                IF x_rc2%ISOPEN THEN CLOSE x_rc2; END IF;
                                note_err('Findings from table and index data', SQLERRM);
                        END;
                        --
                        IF x_errs IS NOT NULL THEN
                            note('warn', 'Some lookups for this subsection failed and the affected values show as unknown or not assessed:<ul>' || x_errs || '</ul>');
                        END IF;
                    END IF;
                END IF;
            END IF;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF x_rc%ISOPEN THEN CLOSE x_rc; END IF;
            errnote('Related table/index analysis', SQLERRM || ' (' || SUBSTR(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 1, 200) || ')');
    END;
    --
    -- optimizer related parameters whose value changed in the last 7 days (AWR snapshots)
    IF v_awr_ok THEN
        DECLARE
            TYPE t_pchg IS RECORD (name VARCHAR2(200), prev_val VARCHAR2(1000), new_val VARCHAR2(1000), chg_time DATE);
            r_pchg  t_pchg;
            l_rc    t_rc;
            l_n     PLS_INTEGER := 0;
        BEGIN
            -- Every snapshot row is compared with the previous snapshot of the same parameter (LAG over all
            -- retained snapshots, so a change at the start of the window is not missed); only changes whose
            -- snapshot ended within the last 7 days are listed. Case-only differences (exact / EXACT) are ignored.
            q := q'[SELECT parameter_name, prev_value, value, change_time FROM (
                        SELECT p.parameter_name, p.value,
                               LAG(p.value) OVER (PARTITION BY p.parameter_name ORDER BY p.snap_id) AS prev_value,
                               ROW_NUMBER() OVER (PARTITION BY p.parameter_name ORDER BY p.snap_id) AS rn,
                               CAST(s.end_interval_time AS DATE) AS change_time
                        FROM dba_hist_parameter p JOIN dba_hist_snapshot s
                          ON s.snap_id = p.snap_id AND s.dbid = p.dbid AND s.instance_number = p.instance_number
                        WHERE p.dbid = (SELECT dbid FROM v$database)
                          AND p.instance_number = TO_NUMBER(SYS_CONTEXT('USERENV', 'INSTANCE'))
                          AND (p.parameter_name LIKE 'optimizer%'
                               OR p.parameter_name IN ('cursor_sharing', 'db_file_multiblock_read_count', 'pga_aggregate_target', 'sga_target', 'memory_target',
                                                       'star_transformation_enabled', 'query_rewrite_enabled', 'parallel_degree_policy', 'workarea_size_policy',
                                                       'statistics_level', 'session_cached_cursors', 'result_cache_mode')))
                    WHERE rn > 1 AND change_time >= SYSDATE - 7
                      AND NVL(UPPER(value), CHR(1)) <> NVL(UPPER(prev_value), CHR(1))
                    ORDER BY change_time DESC, parameter_name]';
            OPEN l_rc FOR q;
            LOOP
                FETCH l_rc INTO r_pchg;
                EXIT WHEN l_rc%NOTFOUND;
                IF l_n = 0 THEN
                    p('<p><b>Optimizer-related parameters whose value changed in the last 7 days</b></p>');
                    tbl_open('Parameter|Previous Value|New Value|Change Seen At (AWR snapshot end)');
                END IF;
                l_n := l_n + 1;
                p('<tr>' || td(r_pchg.name) || td(r_pchg.prev_val) || td(r_pchg.new_val) || td(fts(r_pchg.chg_time), 'nw') || '</tr>');
                v_pchg_n := v_pchg_n + 1;
                v_pchg_txt := SUBSTR(v_pchg_txt || CASE WHEN v_pchg_txt IS NOT NULL THEN '; ' END || r_pchg.name || ' ' || NVL(r_pchg.prev_val, '(null)')
                                     || ' -> ' || NVL(r_pchg.new_val, '(null)') || ' (seen ' || fts(r_pchg.chg_time) || ')', 1, 2000);
            END LOOP;
            CLOSE l_rc;
            IF l_n = 0 THEN
                p('<p>' || badge('Parameters', 'ok') || ' No change in optimizer-related instance parameters was recorded by AWR in the last 7 days. Session-level settings (ALTER SESSION) are not captured by AWR.</p>');
            ELSE
                tbl_close;
                p('<p class="small">Compare with the first-observed times in section 5.3.</p>');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF l_rc%ISOPEN THEN CLOSE l_rc; END IF;
                errnote('Parameter changes', SQLERRM);
        END;
    END IF;
    p('</div>');
    --
    --=========================================================================
    -- SECTION 6 : FINDINGS AND RECOMMENDATIONS
    --=========================================================================
    p('<div class="card" id="sec6">');
    h2('6', 'Findings and Recommendations');
    DECLARE
        -- measured workload of the analysed plan (times in microseconds, as the views report them)
        l_src     VARCHAR2(80);
        l_ex      NUMBER;  l_ela  NUMBER;  l_cpu NUMBER;  l_gets NUMBER;  l_rd  NUMBER;  l_rows NUMBER;
        l_io      NUMBER;  l_cc   NUMBER;  l_ap  NUMBER;  l_cl   NUMBER;  l_pl  NUMBER;  l_prs  NUMBER;
        l_ft      NUMBER;  l_ld   NUMBER;  l_inv NUMBER;  l_dw   NUMBER;  l_so  NUMBER;
        l_exs     NUMBER;            -- executions, never below 1 (used as divisor)
        l_tot     NUMBER;            -- total elapsed seconds
        l_per     NUMBER;            -- elapsed seconds per execution
        l_gpr     NUMBER;            -- buffer gets per row
        l_rpf     NUMBER;            -- rows per fetch
        l_hit     NUMBER;            -- share of buffer gets satisfied from cache
        l_prio    PLS_INTEGER;
        -- plan row-source statistics
        l_child   NUMBER;
        l_id      NUMBER;
        l_op      VARCHAR2(200);
        l_obj     VARCHAR2(200);
        l_st      NUMBER;
        l_ro      NUMBER;
        l_sb      NUMBER;
        l_tb      NUMBER;
        l_e       NUMBER;
        l_a       NUMBER;
        -- cursor flags
        l_bl      NUMBER;  l_pf   NUMBER;  l_pt  NUMBER;  l_bs  NUMBER;  l_ba  NUMBER;  l_ro2 NUMBER;  l_ch  NUMBER;
        -- work areas
        l_wid     NUMBER;
        l_wtyp    VARCHAR2(60);
        l_wopt    NUMBER;  l_wone NUMBER;  l_wmem NUMBER;  l_wtmp NUMBER;
        l_wtot    NUMBER;  l_wopx NUMBER;  l_w1   NUMBER;  l_wm   NUMBER;
        l_pga     NUMBER;
        -- ash
        l_rc2     t_rc;
        l_cause   VARCHAR2(1000);
        l_res     VARCHAR2(2000);
        l_ev1     VARCHAR2(300);  l_wc1 VARCHAR2(100);  l_sm1 NUMBER;  l_pc1 NUMBER;
        l_ev2     VARCHAR2(300);  l_wc2 VARCHAR2(100);  l_sm2 NUMBER;  l_pc2 NUMBER;
        -- blocking
        l_nrun    PLS_INTEGER := 0;
        l_nblk    PLS_INTEGER := 0;
        l_maxw    NUMBER := 0;
        l_roots   VARCHAR2(500);
        TYPE t_evc IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(200);
        l_evc     t_evc;
        l_evk     VARCHAR2(200);
        l_topev   VARCHAR2(200);
        l_topn    PLS_INTEGER := 0;
        -- misc
        l_s       VARCHAR2(4000);
        l_s2      VARCHAR2(4000);
        l_k       PLS_INTEGER;
        l_np      PLS_INTEGER;
        l_mp      PLS_INTEGER;
        l_nc      PLS_INTEGER := 0;
        --
        FUNCTION pc(p_part IN NUMBER) RETURN NUMBER IS
        BEGIN
            RETURN CASE WHEN NVL(l_ela, 0) > 0 AND p_part IS NOT NULL THEN ROUND(100 * p_part / l_ela, 1) END;
        END pc;
        --
        PROCEDURE wrow(p_k IN VARCHAR2, p_v IN VARCHAR2) IS
        BEGIN
            p('<tr>' || td(p_k) || td(p_v, 'r nw') || '</tr>');
        END wrow;
        --
        FUNCTION mbs(p_bytes IN NUMBER) RETURN VARCHAR2 IS
        BEGIN
            RETURN CASE WHEN p_bytes IS NULL THEN '-' ELSE fdec(p_bytes / 1048576, 1) || ' MB' END;
        END mbs;
    BEGIN
        IF v_is_plsql THEN
            note('info', 'Plan-based findings do not apply: this SQL_ID is an anonymous PL/SQL block. The statements it executes (as far as ASH recorded them) are listed below; analyse each of them with this script.');
            DECLARE
                l_rcp   t_rc;
                l_cid   VARCHAR2(30);
                l_csm   NUMBER;
                l_cop   VARCHAR2(60);
                l_ctx   VARCHAR2(200);
                l_cn    PLS_INTEGER := 0;
                l_cview VARCHAR2(40);
            BEGIN
                FOR k IN 1 .. 2 LOOP
                    EXIT WHEN l_cn > 0;
                    IF k = 1 OR v_awr_ok THEN
                        l_cview := CASE k WHEN 1 THEN 'v$active_session_history' ELSE 'dba_hist_active_sess_history' END;
                        BEGIN
                            OPEN l_rcp FOR 'SELECT sql_id, samples, opname, txt FROM (SELECT x.sql_id, COUNT(*) samples, MAX(x.sql_opname) opname, '
                                || '(SELECT SUBSTR(MAX(a.sql_text), 1, 150) FROM v$sqlarea a WHERE a.sql_id = x.sql_id) txt FROM ' || l_cview
                                || ' x WHERE x.top_level_sql_id = :1 AND x.sql_id IS NOT NULL AND x.sql_id <> :2 GROUP BY x.sql_id ORDER BY COUNT(*) DESC) WHERE ROWNUM <= 10'
                                USING v_sql_id, v_sql_id;
                            LOOP
                                FETCH l_rcp INTO l_cid, l_csm, l_cop, l_ctx;
                                EXIT WHEN l_rcp%NOTFOUND;
                                IF l_cn = 0 THEN
                                    tbl_open('SQL_ID|>ASH samples|Operation|SQL text (start)');
                                END IF;
                                l_cn := l_cn + 1;
                                p('<tr>' || td(l_cid, 'nw') || td(fnum(l_csm), 'r') || td(l_cop) || td(l_ctx) || '</tr>');
                            END LOOP;
                            CLOSE l_rcp;
                            IF l_cn > 0 THEN
                                tbl_close;
                                p('<p class="small">Source: ' || upper(l_cview) || ', samples whose TOP_LEVEL_SQL_ID is this block'
                                  || CASE k WHEN 2 THEN ' (AWR keeps one in ten samples)' END || '.</p>');
                            END IF;
                        EXCEPTION
                            WHEN OTHERS THEN
                                IF l_rcp%ISOPEN THEN CLOSE l_rcp; END IF;
                                errnote('Statements run by the PL/SQL block', SQLERRM);
                        END;
                    END IF;
                END LOOP;
                IF l_cn = 0 THEN
                    note('info', 'No statement run by this block was found in ASH. Look for the block''s caller (V$SESSION.PLSQL_ENTRY_OBJECT_ID, or the application) or trace the session.');
                END IF;
            END;
        ELSIF v_cur_phv IS NULL THEN
            note('info', 'No plan is available to analyse (the SQL_ID is in neither the cursor cache nor AWR), so no findings can be derived.');
        ELSE
            p('<p>Analysed plan: <b>' || v_cur_phv || '</b> <span class="small">(' || esc(v_cur_src) || ')</span></p>');
            --
            -- ===================================================================== plan source and structural counts
            v_src_view := NULL;
            BEGIN
                IF cnt('v$sql_plan', '1 = 1') > 0 THEN
                    v_src_view := 'v$sql_plan';
                ELSIF v_awr_ok THEN
                    IF cnt('dba_hist_sql_plan', '1 = 1') > 0 THEN
                        v_src_view := 'dba_hist_sql_plan';
                    END IF;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    v_src_view := NULL;
            END;
            v_full := 0; v_cart := 0; v_hj := 0; v_rowstats := 0; v_misest := 0;
            IF v_src_view IS NOT NULL THEN
                BEGIN
                    v_full := cnt(v_src_view, q'[operation = 'TABLE ACCESS' AND options LIKE '%FULL%']');
                    v_cart := cnt(v_src_view, q'[(options LIKE '%CARTESIAN%' OR operation LIKE '%CARTESIAN%')]');
                    v_hj   := cnt(v_src_view, q'[operation = 'HASH JOIN']');
                EXCEPTION
                    WHEN OTHERS THEN
                        errnote('Plan structure counts', SQLERRM);
                END;
                IF v_src_view = 'v$sql_plan' THEN
                    BEGIN
                        EXECUTE IMMEDIATE 'SELECT COUNT(CASE WHEN last_output_rows IS NOT NULL THEN 1 END), COUNT(CASE WHEN last_output_rows > 0 AND cardinality > 0 AND (last_output_rows / NULLIF(cardinality, 0) > 10 OR cardinality / NULLIF(last_output_rows, 0) > 10) THEN 1 END) FROM v$sql_plan_statistics_all WHERE sql_id = :1 AND plan_hash_value = :2'
                            INTO v_rowstats, v_misest USING v_sql_id, v_cur_phv;
                    EXCEPTION
                        WHEN OTHERS THEN
                            v_rowstats := 0; v_misest := 0;
                    END;
                END IF;
            END IF;
            --
            -- ===================================================================== 6.1 measured workload
            h3('6.1', 'Measured workload of the analysed plan');
            BEGIN
                EXECUTE IMMEDIATE 'SELECT SUM(executions), SUM(elapsed_time), SUM(cpu_time), SUM(buffer_gets), SUM(disk_reads), SUM(rows_processed), SUM(user_io_wait_time), '
                    || 'SUM(concurrency_wait_time), SUM(application_wait_time), SUM(cluster_wait_time), SUM(plsql_exec_time), SUM(parse_calls), SUM(fetches), SUM(loads), '
                    || 'SUM(invalidations), SUM(direct_writes), SUM(sorts) FROM v$sqlstats WHERE sql_id = :1 AND plan_hash_value = :2'
                    INTO l_ex, l_ela, l_cpu, l_gets, l_rd, l_rows, l_io, l_cc, l_ap, l_cl, l_pl, l_prs, l_ft, l_ld, l_inv, l_dw, l_so
                    USING v_sql_id, v_cur_phv;
                IF l_ex IS NOT NULL THEN l_src := 'cursor cache (V$SQLSTATS), accumulated since the cursor was loaded'; END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    l_ex := NULL;
                    errnote('Workload from V$SQLSTATS', SQLERRM);
            END;
            IF l_src IS NULL AND v_awr_ok THEN
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT SUM(h.executions_delta), SUM(h.elapsed_time_delta), SUM(h.cpu_time_delta), SUM(h.buffer_gets_delta), SUM(h.disk_reads_delta), SUM(h.rows_processed_delta), '
                        || 'SUM(h.iowait_delta), SUM(h.ccwait_delta), SUM(h.apwait_delta), SUM(h.clwait_delta), SUM(h.plsexec_time_delta), SUM(h.parse_calls_delta), SUM(h.fetches_delta), '
                        || 'SUM(h.loads_delta), SUM(h.invalidations_delta), SUM(h.direct_writes_delta), SUM(h.sorts_delta) '
                        || 'FROM dba_hist_sqlstat h JOIN dba_hist_snapshot s ON s.snap_id = h.snap_id AND s.dbid = h.dbid AND s.instance_number = h.instance_number '
                        || 'WHERE h.sql_id = :1 AND h.plan_hash_value = :2 AND s.begin_interval_time > SYSTIMESTAMP - 7'
                        INTO l_ex, l_ela, l_cpu, l_gets, l_rd, l_rows, l_io, l_cc, l_ap, l_cl, l_pl, l_prs, l_ft, l_ld, l_inv, l_dw, l_so
                        USING v_sql_id, v_cur_phv;
                    IF l_ex IS NOT NULL THEN l_src := 'AWR (DBA_HIST_SQLSTAT), sum of the snapshot deltas of the last 7 days'; END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        l_ex := NULL;
                        errnote('Workload from AWR', SQLERRM);
                END;
            END IF;
            --
            IF l_src IS NULL THEN
                note('info', 'No execution statistics were found for plan ' || v_cur_phv || ' in V$SQLSTATS or in the last 7 days of AWR. Findings that need workload figures are skipped; findings from the plan, the objects and the parameter history are still given below.');
            ELSE
                l_exs := GREATEST(NVL(l_ex, 0), 1);
                l_tot := NVL(l_ela, 0) / 1000000;
                l_per := l_tot / l_exs;
                l_gpr := CASE WHEN NVL(l_rows, 0) > 0 THEN l_gets / l_rows END;
                l_rpf := CASE WHEN NVL(l_ft, 0) > 0 THEN l_rows / l_ft END;
                l_hit := CASE WHEN NVL(l_gets, 0) > 0 THEN ROUND(100 * (1 - LEAST(NVL(l_rd, 0), l_gets) / l_gets), 1) END;
                IF NVL(l_ex, 0) = 0 THEN
                    note('info', 'The statement has not completed an execution in this window (it may still be running), so per-execution figures below use one execution as divisor and should be read as totals.');
                END IF;
                tbl_open('Metric|>Value');
                wrow('Source', l_src);
                wrow('Executions', fnum(l_ex));
                wrow('Total elapsed time', fdur(l_tot));
                wrow('Elapsed time per execution', fdec(l_per, 3) || ' s');
                wrow('CPU time', fdur(l_cpu / 1000000) || CASE WHEN pc(l_cpu) IS NOT NULL THEN ' (' || fdec(pc(l_cpu), 1) || '% of elapsed)' END);
                wrow('User I/O wait', fdur(l_io / 1000000) || CASE WHEN pc(l_io) IS NOT NULL THEN ' (' || fdec(pc(l_io), 1) || '% of elapsed)' END);
                wrow('Concurrency wait', fdur(l_cc / 1000000) || CASE WHEN pc(l_cc) IS NOT NULL THEN ' (' || fdec(pc(l_cc), 1) || '% of elapsed)' END);
                wrow('Application wait (locks)', fdur(l_ap / 1000000) || CASE WHEN pc(l_ap) IS NOT NULL THEN ' (' || fdec(pc(l_ap), 1) || '% of elapsed)' END);
                wrow('Cluster wait', fdur(l_cl / 1000000) || CASE WHEN pc(l_cl) IS NOT NULL THEN ' (' || fdec(pc(l_cl), 1) || '% of elapsed)' END);
                wrow('PL/SQL execution time', fdur(l_pl / 1000000) || CASE WHEN pc(l_pl) IS NOT NULL THEN ' (' || fdec(pc(l_pl), 1) || '% of elapsed)' END);
                wrow('Buffer gets per execution', fnum(ROUND(l_gets / l_exs)));
                wrow('Physical reads per execution', fnum(ROUND(l_rd / l_exs)));
                wrow('Rows processed per execution', fnum(ROUND(l_rows / l_exs)));
                wrow('Buffer gets per row', CASE WHEN l_gpr IS NULL THEN '-' ELSE fnum(ROUND(l_gpr)) END);
                wrow('Share of buffer gets served from cache', CASE WHEN l_hit IS NULL THEN '-' ELSE fdec(l_hit, 1) || '%' END);
                wrow('Rows per fetch', CASE WHEN l_rpf IS NULL THEN '-' ELSE fdec(l_rpf, 1) END);
                wrow('Parse calls per execution', fdec(NVL(l_prs, 0) / l_exs, 2));
                wrow('Cursor loads / invalidations', fnum(l_ld) || ' / ' || fnum(l_inv));
                tbl_close;
                p('<p class="small">The time components can overlap (PL/SQL time contains the CPU and waits of the code it runs), so they do not add up to 100%.</p>');
            END IF;
            --
            -- ===================================================================== cursor flags (baseline / profile / adaptive cursor sharing)
            BEGIN
                EXECUTE IMMEDIATE 'SELECT COUNT(CASE WHEN sql_plan_baseline IS NOT NULL THEN 1 END), COUNT(CASE WHEN sql_profile IS NOT NULL THEN 1 END), COUNT(CASE WHEN sql_patch IS NOT NULL THEN 1 END), '
                    || 'COUNT(CASE WHEN is_bind_sensitive = ''Y'' THEN 1 END), COUNT(CASE WHEN is_bind_aware = ''Y'' THEN 1 END), COUNT(CASE WHEN is_reoptimizable = ''Y'' THEN 1 END), COUNT(*) '
                    || 'FROM v$sql WHERE sql_id = :1'
                    INTO l_bl, l_pf, l_pt, l_bs, l_ba, l_ro2, l_ch USING v_sql_id;
            EXCEPTION
                WHEN OTHERS THEN
                    l_ch := 0;
            END;
            --
            -- ===================================================================== sessions running this SQL right now (from 4.1)
            IF v_waits.COUNT > 0 THEN
                FOR i IN v_waits.FIRST .. v_waits.LAST LOOP
                    IF v_waits.EXISTS(i) THEN
                        l_nrun := l_nrun + 1;
                        IF v_waits(i).blk_sid IS NOT NULL THEN
                            l_nblk := l_nblk + 1;
                            l_maxw := GREATEST(l_maxw, NVL(v_waits(i).sec_in_wait, 0));
                            IF INSTR(',' || l_roots || ',', ',' || NVL(v_waits(i).final_blk, v_waits(i).blk_sid) || ',') = 0 AND NVL(LENGTH(l_roots), 0) < 400 THEN
                                l_roots := l_roots || CASE WHEN l_roots IS NOT NULL THEN ',' END || NVL(v_waits(i).final_blk, v_waits(i).blk_sid);
                            END IF;
                        END IF;
                        IF v_waits(i).event IS NOT NULL AND NVL(v_waits(i).wait_class, 'x') <> 'Idle' THEN
                            IF l_evc.EXISTS(v_waits(i).event) THEN
                                l_evc(v_waits(i).event) := l_evc(v_waits(i).event) + 1;
                            ELSE
                                l_evc(v_waits(i).event) := 1;
                            END IF;
                        END IF;
                    END IF;
                END LOOP;
                l_evk := l_evc.FIRST;
                WHILE l_evk IS NOT NULL LOOP
                    IF l_evc(l_evk) > l_topn THEN
                        l_topn := l_evc(l_evk);
                        l_topev := l_evk;
                    END IF;
                    l_evk := l_evc.NEXT(l_evk);
                END LOOP;
            END IF;
            --
            -- ===================================================================== findings from the workload
            IF l_src IS NOT NULL THEN
                -- (a) where the time goes
                IF NVL(l_ela, 0) > 0 THEN
                    l_prio := CASE WHEN l_per >= 5 THEN 1 ELSE 2 END;
                    IF pc(l_io) >= 40 THEN
                        fd_add(l_prio, 'Elapsed time is dominated by user I/O (' || fdec(pc(l_io), 0) || '%)',
                            fdur(l_io / 1000000) || ' of the ' || fdur(l_tot) || ' total elapsed time (' || fdec(pc(l_io), 1) || '%) is spent waiting for user I/O. Per execution: '
                              || fnum(ROUND(l_rd / l_exs)) || ' physical reads and ' || fnum(ROUND(l_gets / l_exs)) || ' buffer gets, so ' || fdec(100 - l_hit, 1) || '% of the block requests go to disk; '
                              || fdec(l_per, 3) || ' s per execution over ' || fnum(l_ex) || ' execution(s).',
                            CASE WHEN l_hit >= 95
                                 THEN 'Almost all block requests are served from cache, yet I/O wait dominates, which points at storage latency (or direct-path reads that bypass the cache) rather than at the volume the plan reads. Check the average wait of the top read event in AWR with the storage team, and the direct path read events in section 4.4.'
                                 WHEN v_full > 0
                                 THEN 'The plan contains ' || fnum(v_full) || ' full-scan step(s); the findings on those tables below say which predicate or index is involved. Reducing the blocks read there is the first lever, before any storage-level change.'
                                 ELSE 'The plan has no full scan, so the physical reads come from index and table block access. Look at the index findings below (selectivity, clustering factor) and at the hot plan step in this table.' END,
                            'User I/O wait falls below 40% of elapsed time and physical reads per execution drop in the next window.');
                    ELSIF pc(l_cpu) >= 60 THEN
                        fd_add(l_prio, 'Statement is CPU-bound (' || fdec(pc(l_cpu), 0) || '% of elapsed time)',
                            fdur(l_cpu / 1000000) || ' of ' || fdur(l_tot) || ' elapsed (' || fdec(pc(l_cpu), 1) || '%) is CPU. Per execution: ' || fnum(ROUND(l_gets / l_exs)) || ' buffer gets for '
                              || fnum(ROUND(l_rows / l_exs)) || ' row(s)' || CASE WHEN l_gpr IS NOT NULL THEN ' (' || fnum(ROUND(l_gpr)) || ' buffer gets per row)' END || '; ' || fdec(l_per, 3) || ' s per execution.'
                              || CASE WHEN pc(l_pl) >= 20 THEN ' PL/SQL execution accounts for ' || fdec(pc(l_pl), 1) || '% of the elapsed time.' END,
                            CASE WHEN pc(l_pl) >= 20
                                 THEN 'A fifth or more of the time is PL/SQL called from the SQL: look for scalar functions evaluated per row (inline them, mark them DETERMINISTIC, or use the function result cache) and for row-by-row processing around the statement.'
                                 WHEN l_gpr >= 1000
                                 THEN 'Each returned row costs about ' || fnum(ROUND(l_gpr)) || ' logical reads, so the CPU is spent re-reading blocks. Reducing logical I/O is the lever; see the hot plan step in this table.'
                                 ELSE 'Logical I/O per row is moderate, so the CPU is probably spent on sorting, hashing, expression evaluation or parsing rather than on block reads; compare the work areas and the parse figures in this table.' END,
                            'CPU time per execution (V$SQLSTATS CPU_TIME / EXECUTIONS) falls after the change.');
                    END IF;
                    IF pc(l_ap) >= 20 THEN
                        fd_add(1, 'Time lost to row-lock (application) waits: ' || fdec(pc(l_ap), 0) || '%',
                            fdur(l_ap / 1000000) || ' of ' || fdur(l_tot) || ' elapsed (' || fdec(pc(l_ap), 1) || '%) is application wait, which is mostly row-lock and enqueue waiting on other sessions'' transactions.',
                            'The statement is slow because it waits for locks held by other transactions, not because of its plan. Identify the blockers (section 4.1/4.2 while it is happening, or ASH for the past: BLOCKING_SESSION of the samples), shorten the blocking transactions (commit sooner, no think time while rows are locked), and check for unindexed foreign keys on the tables it modifies.',
                            'Application wait falls under 5% of elapsed time.');
                    END IF;
                    IF pc(l_cc) >= 20 THEN
                        IF l_topev IS NOT NULL THEN
                            advice(l_topev, 'Concurrency', l_cause, l_res);
                        ELSE
                            l_cause := NULL;
                            l_res := 'Find the event in section 4.4 (ASH) and act on it: hot blocks need fewer logical reads per execution; library cache or mutex events point at cursor sharing, parse rate and invalidations.';
                        END IF;
                        fd_add(2, 'Concurrency waits take ' || fdec(pc(l_cc), 0) || '% of the time',
                            fdur(l_cc / 1000000) || ' of ' || fdur(l_tot) || ' elapsed (' || fdec(pc(l_cc), 1) || '%) is concurrency wait (latches, mutexes, buffer busy, library cache).'
                              || CASE WHEN l_topev IS NOT NULL THEN ' Right now ' || fnum(l_topn) || ' of the ' || fnum(l_nrun) || ' session(s) running this SQL show ' || l_topev || ' as their current or last wait.' END
                              || CASE WHEN l_cause IS NOT NULL THEN ' ' || l_cause END,
                            l_res,
                            'Concurrency wait drops under 5% of elapsed time and the event disappears from the sessions listed in 4.1.');
                    END IF;
                    IF pc(l_cl) >= 20 THEN
                        fd_add(2, 'Cluster (RAC) waits take ' || fdec(pc(l_cl), 0) || '% of the time',
                            fdur(l_cl / 1000000) || ' of ' || fdur(l_tot) || ' elapsed (' || fdec(pc(l_cl), 1) || '%) is cluster wait: blocks are being shipped between instances.',
                            'Run the statement on one instance through a service with a preferred instance, or partition the workload by instance; check interconnect latency if the waits are gc buffer busy / gc cr events.',
                            'Cluster wait falls under 10% of elapsed time.');
                    END IF;
                END IF;
                --
                -- (b) logical I/O per row
                IF l_gpr >= 1000 AND NVL(l_rows, 0) > 0 THEN
                    fd_add(2, 'High logical I/O per returned row (' || fnum(ROUND(l_gpr)) || ' buffer gets per row)',
                        fnum(ROUND(l_gets / l_exs)) || ' buffer gets per execution to return ' || fnum(ROUND(l_rows / l_exs)) || ' row(s); ' || fdec(l_hit, 1) || '% of them are served from cache.',
                        'The statement reads far more blocks than it returns rows. Typical causes are an unselective index range scan followed by table access and filtering, a nested-loop join driven by too many outer rows, or a full scan with a selective filter; the hot plan step in this table and the full-scan findings show which one applies.',
                        'Buffer gets per row fall by an order of magnitude after the change.');
                END IF;
                --
                -- (c) high-frequency statement
                IF NVL(l_ex, 0) >= 1000 AND l_per < 0.05 AND l_tot >= 60 THEN
                    fd_add(3, 'High-frequency statement: ' || fnum(l_ex) || ' executions',
                        fnum(l_ex) || ' executions at ' || fdec(l_per * 1000, 2) || ' ms each add up to ' || fdur(l_tot) || ' of database time' || CASE WHEN l_src LIKE 'AWR%' THEN ' in the last 7 days' END || '. Parse calls per execution: ' || fdec(NVL(l_prs, 0) / l_exs, 2) || '.',
                        'Each call is cheap, so tuning the plan helps little; the saving is in calling it less: batch the work (array processing, one join instead of a lookup per row), cache the result in the application, or remove polling.'
                          || CASE WHEN NVL(l_prs, 0) >= 0.9 * l_ex THEN ' The cursor is parsed on almost every execution: keep it open in the application or raise SESSION_CACHED_CURSORS.' END,
                        'Executions per hour fall, or parse calls per execution drop towards zero.');
                END IF;
                --
                -- (d) invalidations
                IF NVL(l_inv, 0) >= 5 THEN
                    fd_add(2, 'Cursor invalidated ' || fnum(l_inv) || ' times (loaded ' || fnum(l_ld) || ' times)',
                        'V$SQLSTATS records ' || fnum(l_inv) || ' invalidations and ' || fnum(l_ld) || ' loads for this plan. Every invalidation forces a re-parse and gives the optimizer a chance to pick a different plan.',
                        'Find what keeps invalidating it: DDL on a referenced table (see the Last DDL and DML table in 5.4), statistics gathers that invalidate dependent cursors immediately (NO_INVALIDATE => FALSE), or an undersized shared pool. Gathering with the default AUTO_INVALIDATE spreads the re-parses over time.',
                        'The invalidation count stops growing between two runs of this report.');
                END IF;
                --
                -- (e) fetch size
                IF NVL(l_ft, 0) > 0 AND l_rpf <= 2 AND l_rows / l_exs >= 100 THEN
                    fd_add(3, 'Very small fetch size: ' || fdec(l_rpf, 1) || ' rows per fetch',
                        fnum(ROUND(l_rows / l_exs)) || ' rows per execution are returned in ' || fnum(ROUND(l_ft / l_exs)) || ' fetch call(s) per execution, i.e. ' || fdec(l_rpf, 1) || ' row(s) per round trip.',
                        'Raise the client array size to 100-500 (JDBC setFetchSize, OCI prefetch, SQL*Plus ARRAYSIZE). Each fetch is a network round trip and extra logical reads for the same block.',
                        'Fetches per execution fall roughly in proportion; SQL*Net message to client waits shrink in section 4.4.');
                END IF;
            END IF;
            --
            -- ===================================================================== plan instability, baselines, parameter changes
            IF v_n_plans > 1 THEN
                l_s := v_n_plans || ' plan hash values have been observed for this SQL_ID'
                       || CASE WHEN v_children > 1 THEN ' and ' || v_children || ' child cursors exist (' || v_child_envs || ' distinct optimizer environment(s))' END || '.'
                       || CASE WHEN v_best IS NOT NULL AND v_best > 0
                               THEN ' Plan ' || v_best_phv || ' is the fastest at ' || fdec(v_best, 3) || ' s per execution, plan ' || v_worst_phv || ' the slowest at ' || fdec(v_worst, 3) || ' s ('
                                    || fdec(v_worst / v_best, 1) || 'x). The analysed plan is ' || v_cur_phv || CASE WHEN v_cur_phv = v_worst_phv THEN ', the slowest one' WHEN v_cur_phv = v_best_phv THEN ', the fastest one' ELSE ', neither the fastest nor the slowest' END || '.' END
                       || CASE WHEN v_chg_date IS NOT NULL THEN ' The analysed plan was first seen in AWR at ' || fts(v_chg_date) || '.' END
                       || CASE WHEN l_ch > 0 THEN ' Cursor flags: ' || fnum(l_bl) || ' child(ren) use a SQL plan baseline, ' || fnum(l_pf) || ' a SQL profile, ' || fnum(l_pt) || ' a SQL patch; '
                                    || fnum(l_bs) || ' bind-sensitive, ' || fnum(l_ba) || ' bind-aware, ' || fnum(l_ro2) || ' marked for re-optimisation.' END;
                IF v_best IS NOT NULL AND v_best > 0 AND v_worst / v_best >= 2 THEN
                    fd_add(CASE WHEN v_cur_phv = v_worst_phv THEN 1 ELSE 2 END,
                        'Plan instability: plan ' || v_worst_phv || ' is ' || fdec(v_worst / v_best, 1) || 'x slower than plan ' || v_best_phv,
                        l_s,
                        CASE WHEN l_bl > 0
                             THEN 'A SQL plan baseline is already attached to some children; check DBA_SQL_PLAN_BASELINES for ACCEPTED plans and whether plan ' || v_best_phv || ' is among them (evolve it if it is not). '
                             ELSE 'First find out why the plan changed (statistics, parameter or DDL findings in this table are candidates). To keep the fast plan meanwhile, load it as a baseline while it is still in the cursor cache: DECLARE n PLS_INTEGER; BEGIN n := DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(sql_id => '''
                                  || v_sql_id || ''', plan_hash_value => ' || v_best_phv || '); END;  (SQL Plan Management needs Enterprise Edition; if the plan has aged out, load it from an AWR-based SQL tuning set, which needs the Tuning Pack.) ' END
                          || CASE WHEN NVL(l_bs, 0) > 0 THEN 'Some cursors are bind-sensitive, so the variation may be adaptive cursor sharing reacting to different bind values: compare the peeked binds in section 4 before pinning a single plan.' END,
                        'One plan hash value remains in V$SQLSTATS and the elapsed time per execution matches plan ' || v_best_phv || '.');
                ELSE
                    fd_add(3, 'Several plans, similar performance',
                        l_s,
                        'The plans differ in shape but their average elapsed times are within 2x of each other, so there is no evidence that the plan change hurts. No action is needed unless the elapsed time per execution worsens.',
                        'Re-run this report after a change in statistics or parameters.');
                END IF;
            END IF;
            --
            IF NVL(v_pchg_n, 0) > 0 THEN
                fd_add(2, fnum(v_pchg_n) || ' optimizer-related parameter change(s) in the last 7 days',
                    v_pchg_txt || '.' || CASE WHEN v_chg_date IS NOT NULL AND v_chg_date >= SYSDATE - 7 THEN ' The analysed plan first appeared in AWR at ' || fts(v_chg_date) || ', inside the same window.' END,
                    'Confirm each change with its owner. To test whether a parameter drives the plan, run the statement in a test session with ALTER SESSION SET <parameter> = <previous value> and compare the plans (section 1.6 shows the outline). If a change is confirmed harmful, revert it or confine it with an OPT_PARAM hint instead of a system-wide setting.',
                    'The plan under the previous parameter value matches the faster plan in section 5.');
            END IF;
            --
            -- ===================================================================== plan-based findings (cartesian joins, hot step, misestimates)
            IF v_src_view IS NOT NULL THEN
                IF v_cart > 0 THEN
                    BEGIN
                        l_s := NULL;
                        OPEN l_rc2 FOR 'SELECT DISTINCT id, cardinality FROM ' || v_src_view || ' WHERE sql_id = :1 AND plan_hash_value = :2 AND (options LIKE ''%CARTESIAN%'' OR operation LIKE ''%CARTESIAN%'') ORDER BY id'
                            USING v_sql_id, v_cur_phv;
                        LOOP
                            FETCH l_rc2 INTO l_id, l_e;
                            EXIT WHEN l_rc2%NOTFOUND;
                            l_s := l_s || CASE WHEN l_s IS NOT NULL THEN '; ' END || 'step ' || l_id || ' (estimated ' || fnum(l_e) || ' row(s))';
                        END LOOP;
                        CLOSE l_rc2;
                    EXCEPTION
                        WHEN OTHERS THEN
                            IF l_rc2%ISOPEN THEN CLOSE l_rc2; END IF;
                    END;
                    fd_add(1, 'Cartesian join in the plan',
                        fnum(v_cart) || ' cartesian join step(s): ' || NVL(l_s, 'see the plan') || '. Every row of one input is combined with every row of the other, so the cost grows with the product of the two row counts.',
                        'Check the join predicates between the two row sources in section 1.6: a missing or mistyped join condition is the usual cause. If it is deliberate (a one-row inline view), confirm the estimate of that input is really one row.',
                        'The plan no longer contains MERGE JOIN CARTESIAN / BUFFER SORT.');
                END IF;
                --
                IF v_full > 0 AND NOT v_fd_full THEN
                    BEGIN
                        l_s := NULL;
                        OPEN l_rc2 FOR 'SELECT DISTINCT id, object_owner || ''.'' || object_name FROM ' || v_src_view || ' WHERE sql_id = :1 AND plan_hash_value = :2 AND operation = ''TABLE ACCESS'' AND options LIKE ''%FULL%'' ORDER BY id'
                            USING v_sql_id, v_cur_phv;
                        LOOP
                            FETCH l_rc2 INTO l_id, l_obj;
                            EXIT WHEN l_rc2%NOTFOUND OR l_nc >= 5;
                            l_nc := l_nc + 1;
                            l_s := l_s || CASE WHEN l_s IS NOT NULL THEN '; ' END || 'step ' || l_id || ' on ' || l_obj;
                        END LOOP;
                        CLOSE l_rc2;
                    EXCEPTION
                        WHEN OTHERS THEN
                            IF l_rc2%ISOPEN THEN CLOSE l_rc2; END IF;
                    END;
                    fd_add(3, 'Full table scan in the plan',
                        fnum(v_full) || ' full-scan step(s): ' || NVL(l_s, 'see the plan') || '. The table dictionary views could not be read, so predicates, sizes and candidate indexes were not analysed.',
                        'Grant the privileges listed in the script header (DBA_TAB_STATISTICS, DBA_IND_COLUMNS, DBA_SEGMENTS) and re-run, or inspect the filter predicate of these steps in section 1.6.',
                        'Re-run the report with the privileges in place.');
                END IF;
                --
                -- hot step and worst non-object misestimate need row-source statistics of the last execution
                IF v_src_view = 'v$sql_plan' AND v_rowstats > 0 THEN
                    BEGIN
                        EXECUTE IMMEDIATE 'SELECT MAX(child_number) FROM v$sql_plan_statistics_all WHERE sql_id = :1 AND plan_hash_value = :2 AND last_starts > 0'
                            INTO l_child USING v_sql_id, v_cur_phv;
                        IF l_child IS NOT NULL THEN
                            EXECUTE IMMEDIATE 'SELECT NVL(last_cr_buffer_gets, 0) + NVL(last_cu_buffer_gets, 0) FROM v$sql_plan_statistics_all WHERE sql_id = :1 AND plan_hash_value = :2 AND child_number = :3 AND id = 0'
                                INTO l_tb USING v_sql_id, v_cur_phv, l_child;
                            -- self buffer gets of a step = its cumulative buffer gets minus those of its direct children
                            EXECUTE IMMEDIATE 'SELECT id, operation || NVL('' '' || options, ''''), object_name, last_starts, last_output_rows, self_buf FROM ('
                                || 'SELECT p.id, p.operation, p.options, p.object_name, p.last_starts, p.last_output_rows, '
                                || 'NVL(p.last_cr_buffer_gets, 0) + NVL(p.last_cu_buffer_gets, 0) - NVL(SUM(NVL(c.last_cr_buffer_gets, 0) + NVL(c.last_cu_buffer_gets, 0)), 0) self_buf '
                                || 'FROM v$sql_plan_statistics_all p LEFT JOIN v$sql_plan_statistics_all c ON c.sql_id = p.sql_id AND c.plan_hash_value = p.plan_hash_value AND c.child_number = p.child_number AND c.parent_id = p.id '
                                || 'WHERE p.sql_id = :1 AND p.plan_hash_value = :2 AND p.child_number = :3 '
                                || 'GROUP BY p.id, p.operation, p.options, p.object_name, p.last_starts, p.last_output_rows, p.last_cr_buffer_gets, p.last_cu_buffer_gets '
                                || 'ORDER BY 7 DESC) WHERE ROWNUM = 1'
                                INTO l_id, l_op, l_obj, l_st, l_ro, l_sb USING v_sql_id, v_cur_phv, l_child;
                            IF NVL(l_tb, 0) > 0 AND NVL(l_sb, 0) > 0 THEN
                                fd_add(CASE WHEN l_sb >= 0.5 * l_tb AND l_tb >= 100000 THEN 2 ELSE 3 END,
                                    'Most of the work is in plan step ' || l_id || ': ' || l_op || CASE WHEN l_obj IS NOT NULL THEN ' ' || l_obj END,
                                    'In the last execution this step used ' || fnum(l_sb) || ' of the statement''s ' || fnum(l_tb) || ' buffer gets (' || fdec(100 * l_sb / l_tb, 0) || '%). It was started '
                                      || fnum(l_st) || ' time(s) and produced ' || fnum(l_ro) || ' row(s)' || CASE WHEN l_st > 1 THEN ' in total (' || fdec(l_ro / l_st, 1) || ' per start, ' || fnum(ROUND(l_sb / l_st)) || ' buffer gets per start)' END || '.',
                                    CASE WHEN l_st >= 1000 AND (l_op LIKE 'TABLE ACCESS BY%' OR l_op LIKE 'INDEX%')
                                         THEN 'The step sits on the inner side of a nested loop that runs it ' || fnum(l_st) || ' times. Check the row estimate of the outer input (E-Rows against A-Rows in 1.6): if the outer side returns far more rows than estimated, a hash join would be cheaper; if the estimate is right, a covering index or a different join order avoids repeating the lookup.'
                                         WHEN l_op LIKE 'TABLE ACCESS FULL%'
                                         THEN 'A single full scan carries most of the cost; the full-scan finding for ' || l_obj || ' shows its predicate and whether an index could serve it.'
                                         WHEN l_op LIKE 'INDEX%'
                                         THEN 'An index access dominates: check how many entries are scanned against how many survive (ACCESS versus FILTER predicates in 1.6); if most index entries are discarded, a better column order or an additional column in the index is the lever.'
                                         ELSE 'Review this step first in the plan of section 1.6: it is where tuning effort pays off.' END,
                                    'The buffer gets of this step (A-Buffers in the plan with GATHER_PLAN_STATISTICS) fall after the change.');
                            END IF;
                            -- worst misestimate on a step without an object (join, aggregation, view)
                            BEGIN
                                EXECUTE IMMEDIATE 'SELECT id, operation || NVL('' '' || options, ''''), est, act FROM (SELECT id, operation, options, cardinality est, last_output_rows / last_starts act FROM v$sql_plan_statistics_all '
                                    || 'WHERE sql_id = :1 AND plan_hash_value = :2 AND child_number = :3 AND object_name IS NULL AND last_starts > 0 AND last_output_rows IS NOT NULL AND cardinality > 0 '
                                    || 'AND (last_output_rows / last_starts > 0) ORDER BY GREATEST(cardinality, last_output_rows / last_starts) / LEAST(cardinality, last_output_rows / last_starts) DESC) WHERE ROWNUM = 1'
                                    INTO l_id, l_op, l_e, l_a USING v_sql_id, v_cur_phv, l_child;
                                IF GREATEST(l_e, l_a) / GREATEST(LEAST(l_e, l_a), 1) >= 10 THEN
                                    fd_add(2, 'Cardinality misestimate at plan step ' || l_id || ' (' || l_op || ')',
                                        'Estimated ' || fnum(l_e) || ' row(s) per start, actual ' || fnum(l_a) || ' (' || fdec(GREATEST(l_e, l_a) / GREATEST(LEAST(l_e, l_a), 1), 0) || 'x). '
                                          || fnum(v_misest) || ' step(s) of the plan are off by more than 10x in total.',
                                        'An error at a join or aggregation step usually comes from the steps below it: follow the first step, going down the plan, whose estimate is already wrong, and treat that table (statistics, histograms, column group) as the finding. Errors that grow at every join point to correlated join columns; extended statistics or a SQL profile address that.',
                                        'E-Rows and A-Rows agree within 10x at this step.');
                                END IF;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN NULL;
                                WHEN OTHERS THEN NULL;
                            END;
                        END IF;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            NULL;
                        WHEN OTHERS THEN
                            errnote('Row-source statistics', SQLERRM);
                    END;
                ELSIF v_src_view = 'v$sql_plan' THEN
                    note('info', 'The hot-step and cardinality checks were skipped: no actual row counts were collected for this cursor (they need STATISTICS_LEVEL = ALL or the GATHER_PLAN_STATISTICS hint).');
                END IF;
            END IF;
            --
            -- ===================================================================== work-area spills
            BEGIN
                EXECUTE IMMEDIATE 'SELECT * FROM (SELECT operation_id, operation_type, MAX(estimated_optimal_size), MAX(estimated_onepass_size), MAX(last_memory_used), MAX(max_tempseg_size), '
                    || 'SUM(total_executions), SUM(optimal_executions), SUM(onepass_executions), SUM(multipasses_executions) FROM v$sql_workarea '
                    || 'WHERE sql_id = :1 GROUP BY operation_id, operation_type HAVING SUM(onepass_executions) + SUM(multipasses_executions) > 0 '
                    || 'ORDER BY SUM(multipasses_executions) * 10 + SUM(onepass_executions) DESC) WHERE ROWNUM = 1'
                    INTO l_wid, l_wtyp, l_wopt, l_wone, l_wmem, l_wtmp, l_wtot, l_wopx, l_w1, l_wm USING v_sql_id;
            EXCEPTION
                WHEN OTHERS THEN
                    l_wid := NULL;
            END;
            IF l_wid IS NOT NULL THEN
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT TO_NUMBER(value) FROM v$parameter WHERE name = ''pga_aggregate_target''' INTO l_pga;
                EXCEPTION
                    WHEN OTHERS THEN l_pga := NULL;
                END;
                fd_add(CASE WHEN NVL(l_wm, 0) > 0 THEN 1 ELSE 2 END,
                    'Work area of plan step ' || l_wid || ' (' || l_wtyp || ') spills to temp',
                    'Of ' || fnum(l_wtot) || ' execution(s) of this work area, ' || fnum(l_wopx) || ' ran in memory, ' || fnum(l_w1) || ' needed one pass over temp and ' || fnum(l_wm)
                      || ' needed several passes. The optimal in-memory size is about ' || mbs(l_wopt) || ', the one-pass size ' || mbs(l_wone) || '; the last execution got ' || mbs(l_wmem)
                      || ' and the largest temp segment was ' || mbs(l_wtmp) || '.' || CASE WHEN l_pga IS NOT NULL THEN ' PGA_AGGREGATE_TARGET is ' || mbs(l_pga) || '.' END,
                    'A single work area receives only a fraction of PGA_AGGREGATE_TARGET, so reaching ' || mbs(l_wopt) || ' by raising the target alone is rarely practical. Reduce the rows sorted or hashed instead: apply filters earlier, drop columns that are not needed from the select list, or change the join order so the smaller input is hashed.'
                      || CASE WHEN NVL(l_wm, 0) > 0 THEN ' Multi-pass executions are the expensive case and justify acting first.' END,
                    'V$SQL_WORKAREA shows OPTIMAL_EXECUTIONS growing while ONEPASS and MULTIPASSES stop growing for this step.');
            END IF;
            --
            -- ===================================================================== historical wait profile
            IF v_awr_ok THEN
                BEGIN
                    OPEN l_rc2 FOR 'SELECT event, wclass, samples, pct FROM (SELECT NVL(event, ''CPU + Wait for CPU'') event, NVL(wait_class, ''CPU'') wclass, COUNT(*) samples, '
                        || 'ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) pct FROM dba_hist_active_sess_history WHERE sql_id = :1 AND sample_time > SYSDATE - 7 '
                        || 'GROUP BY NVL(event, ''CPU + Wait for CPU''), NVL(wait_class, ''CPU'') ORDER BY COUNT(*) DESC) WHERE ROWNUM <= 2'
                        USING v_sql_id;
                    FETCH l_rc2 INTO l_ev1, l_wc1, l_sm1, l_pc1;
                    IF l_rc2%FOUND THEN
                        FETCH l_rc2 INTO l_ev2, l_wc2, l_sm2, l_pc2;
                        IF l_rc2%NOTFOUND THEN l_ev2 := NULL; END IF;
                    END IF;
                    CLOSE l_rc2;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF l_rc2%ISOPEN THEN CLOSE l_rc2; END IF;
                        l_ev1 := NULL;
                END;
                IF l_ev1 IS NOT NULL AND l_ev1 NOT LIKE 'CPU%' AND l_pc1 >= 25 THEN
                    advice(l_ev1, l_wc1, l_cause, l_res);
                    fd_add(2, 'Top historical wait: ' || l_ev1 || ' (' || fdec(l_pc1, 0) || '% of active time)',
                        'In the last 7 days of ASH history, ' || l_ev1 || ' (' || l_wc1 || ') accounts for ' || fnum(l_sm1) || ' sample(s), ' || fdec(l_pc1, 1) || '% of the time this SQL was active (about ' || fdur(l_sm1 * 10) || ')'
                          || CASE WHEN l_ev2 IS NOT NULL THEN '; next is ' || l_ev2 || ' with ' || fdec(l_pc2, 1) || '%' END || '. ' || l_cause,
                        l_res,
                        'The share of this event falls in the next 7-day ASH profile (section 4.4).');
                END IF;
            END IF;
            --
            -- ===================================================================== sessions blocked right now
            IF l_nrun > 0 THEN
                IF l_nblk > 0 THEN
                    fd_add(1, fnum(l_nblk) || ' session(s) running this SQL are blocked right now',
                        fnum(l_nrun) || ' session(s) are executing this SQL_ID; ' || fnum(l_nblk) || ' are waiting on another session. The longest current wait is ' || fdur(l_maxw) || '. Root blocker SID(s): ' || l_roots || '.',
                        'Look at what the root blocker is doing (section 4.2/4.3) before acting: if it is an idle session holding an uncommitted transaction, the application owner should commit or roll back; terminate it only on their instruction. Killing a session rolls back its work, which can itself take long.',
                        'The blocked sessions disappear from section 4.1.');
                END IF;
            END IF;
            --
            -- ===================================================================== print
            h3('6.2', 'Findings and recommendations');
            IF v_nfd = 0 THEN
                note('ok', 'No finding crossed its threshold for this SQL_ID and plan ' || v_cur_phv || '. Measured elapsed time per execution: '
                           || CASE WHEN l_src IS NOT NULL THEN fdec(l_per, 3) || ' s over ' || fnum(l_ex) || ' execution(s)' ELSE 'not available' END
                           || '. If the SQL is still slow for its users, the cause is probably outside the statement and its objects: check the caller (network, application think time) and the instance-level waits.');
            ELSE
                l_np := 0; l_s2 := NULL; l_mp := NULL;
                FOR pr IN 1 .. 3 LOOP
                    FOR i IN 1 .. v_nfd LOOP
                        IF v_fd(i).prio = pr THEN
                            IF l_s2 IS NULL THEN l_s2 := v_fd(i).title; l_mp := pr; END IF;
                            IF pr = 1 THEN l_np := l_np + 1; END IF;
                        END IF;
                    END LOOP;
                END LOOP;
                note(CASE l_mp WHEN 1 THEN 'bad' WHEN 2 THEN 'warn' ELSE 'info' END,
                     '<b>Main finding:</b> ' || esc(l_s2) || '. ' || fnum(v_nfd) || ' finding(s) in total (' || fnum(l_np) || ' High), listed most important first.');
                tbl_open('#|Priority|Finding|Evidence from this SQL_ID|Recommended action');
                l_k := 0;
                FOR pr IN 1 .. 3 LOOP
                    FOR i IN 1 .. v_nfd LOOP
                        IF v_fd(i).prio = pr THEN
                            l_k := l_k + 1;
                            p('<tr>' || td(TO_CHAR(l_k)) || tdh(badge(CASE pr WHEN 1 THEN 'High' WHEN 2 THEN 'Review' ELSE 'Info' END, CASE pr WHEN 1 THEN 'bad' WHEN 2 THEN 'warn' ELSE 'info' END), 'nw')
                              || tdh('<b>' || esc(v_fd(i).title) || '</b>') || td(v_fd(i).evid) || td(v_fd(i).rec) || '</tr>');
                        END IF;
                    END LOOP;
                END LOOP;
                tbl_close;
            END IF;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            errnote('Findings', SQLERRM);
    END;
    p('</div>');
    --
    p('<div class="small" style="text-align:center;margin:14px 0">End of report for SQL_ID ' || esc(v_sql_id) || ' - generated '
      || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || '</div>');
    p('</div></body></html>');
    --
EXCEPTION
    WHEN OTHERS THEN
        p('<div class="card"><div class="note bad"><b>The report generator stopped on an unexpected error:</b> <code>' || esc(SUBSTR(SQLERRM, 1, 500)) || '</code></div></div>');
        p('</div></body></html>');
END;
/

SPOOL OFF
SET DEFINE ON
SET TERMOUT ON
SET HEADING ON
SET PAGESIZE 1000
SET FEEDBACK ON
PROMPT
PROMPT HTML report written to: &&v_rpt_file
PROMPT

-- Optional e-mail (off by default; set send_mail = Y at the top). This is an operating-system
-- command and does not touch the database.
-- The command is written to a one-line temporary script and run with @, instead of being held in a
-- substitution variable and typed as "&&mail_cmd" (SQL*Plus could not parse that line: SP2-0042).
SET TERMOUT OFF
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 1000
SET TRIMSPOOL ON
SET VERIFY OFF
SPOOL sqlid_mail_run_&&v_sql_id..sql
SELECT CASE WHEN UPPER('&&send_mail') = 'Y'
            THEN 'HOST &&rpt_python &&rpt_helper --html "&&v_rpt_file" --sql-id "&&v_sql_id" --db "&&v_rpt_db"'
            ELSE 'PROMPT E-mail not sent (send_mail = N).' END
FROM dual;
SPOOL OFF
SET TERMOUT ON
SET FEEDBACK ON
@sqlid_mail_run_&&v_sql_id..sql
HOST rm -f sqlid_mail_run_&&v_sql_id..sql

#!/usr/bin/env python3
"""
sqlid_mail.py - optional e-mail delivery for the HTML report written by
sqlid_diagnostic_v2.sql.  Standard library only, Python 3.6+.

The SQL script already produces the finished HTML file; this helper only asks
for an e-mail address, validates it and sends the report (HTML body + attachment).
Press Enter at the prompt to skip sending.

SMTP settings come from environment variables (same names as before):
    SMTP_HOST      default localhost
    SMTP_PORT      default 25   (587 for starttls, 465 for ssl)
    SMTP_SECURITY  none | starttls | ssl      (default none)
    SMTP_USER      optional login
    SMTP_PASSWORD  optional password
    SMTP_FROM      default sqlid-diagnostic@<this host>

Usage (called from the SQL script):
    python3 sqlid_mail.py --html report.html --sql-id 4tr9z835vznaz --db ORCL
"""
import argparse
import os
import re
import smtplib
import socket
import ssl
import sys
from email.message import EmailMessage

EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$")


def valid_email(addr: str) -> bool:
    return bool(EMAIL_RE.match(addr)) and len(addr) <= 254 and ".." not in addr


def ask_address(max_tries: int = 3):
    for attempt in range(max_tries):
        try:
            addr = input("Enter e-mail address to send the report to (blank = do not send): ").strip()
        except EOFError:
            return None
        if not addr:
            return None
        if valid_email(addr):
            return addr
        print("  '%s' is not a valid e-mail address (%d attempt(s) left)." % (addr, max_tries - attempt - 1))
    return None


def send(path: str, to_addr: str, sql_id: str, db: str) -> None:
    host = os.environ.get("SMTP_HOST", "localhost")
    port = int(os.environ.get("SMTP_PORT", "25"))
    security = os.environ.get("SMTP_SECURITY", "none").lower()
    user = os.environ.get("SMTP_USER")
    password = os.environ.get("SMTP_PASSWORD")
    sender = os.environ.get("SMTP_FROM", "sqlid-diagnostic@" + socket.getfqdn())

    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        html = fh.read()

    msg = EmailMessage()
    msg["Subject"] = "SQL_ID diagnostic report %s (%s)" % (sql_id, db or "database")
    msg["From"] = sender
    msg["To"] = to_addr
    msg.set_content("The SQL_ID diagnostic report is attached (HTML). Open it in a browser.")
    msg.add_alternative(html, subtype="html")
    msg.add_attachment(html.encode("utf-8"), maintype="text", subtype="html",
                       filename=os.path.basename(path))

    if security == "ssl":
        server = smtplib.SMTP_SSL(host, port, context=ssl.create_default_context(), timeout=30)
    else:
        server = smtplib.SMTP(host, port, timeout=30)
    try:
        if security == "starttls":
            server.starttls(context=ssl.create_default_context())
        if user:
            server.login(user, password or "")
        server.send_message(msg)
    finally:
        server.quit()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--html", required=True)
    ap.add_argument("--sql-id", default="")
    ap.add_argument("--db", default="")
    args = ap.parse_args()

    if not os.path.isfile(args.html):
        print("Report file not found: " + args.html)
        return 1
    print("Report: " + os.path.abspath(args.html))
    addr = ask_address()
    if not addr:
        print("No e-mail sent.")
        return 0
    try:
        send(args.html, addr, args.sql_id, args.db)
        print("Report sent to " + addr)
    except Exception as exc:  # network / auth problems should not break the SQL*Plus session
        print("E-mail could not be sent: %s" % exc)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

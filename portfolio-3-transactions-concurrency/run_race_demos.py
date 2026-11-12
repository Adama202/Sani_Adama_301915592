#!/usr/bin/env python3
"""Runs the six P3 concurrency demos with TWO real database sessions (psycopg2).
Everything printed is real output from this run; it is also saved by run_p3.sh to
race_demos_output.log. Test row: Jabi / Croissant / today, reset to 5 units per part."""
import threading, time, sys
import psycopg2
from psycopg2 import extensions as ext, errors

DB = "crumble"
def conn(iso=ext.ISOLATION_LEVEL_READ_COMMITTED):
    c = psycopg2.connect(dbname=DB)
    c.set_isolation_level(iso)
    c.cursor().execute("SET lock_timeout='15s'"); c.commit()
    return c
def say(*a): print(*a, flush=True)

admin = conn(); admin.autocommit = True
a = admin.cursor()
a.execute("""SELECT os.stock_id FROM outlet_stock os JOIN outlet o USING (outlet_id) JOIN product p USING (product_id)
             WHERE o.name ILIKE '%Jabi%' AND p.name = 'Croissant' AND os.stock_date = CURRENT_DATE""")
ROW = a.fetchone()[0]
a.execute("""SELECT os.stock_id FROM outlet_stock os WHERE os.outlet_id=(SELECT outlet_id FROM outlet_stock WHERE stock_id=%s)
             AND os.stock_date=CURRENT_DATE AND os.stock_id<>%s ORDER BY stock_id LIMIT 1""", (ROW, ROW))
ROW2 = a.fetchone()[0]
def reset(q=5):
    a.execute("UPDATE outlet_stock SET quantity_left=%s WHERE stock_id=%s", (q, ROW))
def stock():
    a.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s", (ROW,)); return a.fetchone()[0]
def bg(fn):
    box = {}
    def run():
        try: box["r"] = fn()
        except Exception as e: box["e"] = e
    t = threading.Thread(target=run); t.start(); return t, box

say("Test row: outlet_stock.stock_id =", ROW, "(Jabi, Croissant, today). Each customer wants 3; stock is 5.")

# ---- Part 1: the bug --------------------------------------------------------
say("\n=== PART 1: the bug - read, then write (lost update / oversell) ===")
reset(); s1, s2 = conn(), conn(); c1, c2 = s1.cursor(), s2.cursor()
c1.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s", (ROW,)); q1 = c1.fetchone()[0]
c2.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s", (ROW,)); q2 = c2.fetchone()[0]
say(f"S1 reads {q1}; S2 reads {q2}  (both think 3 are available)")
c1.execute("UPDATE outlet_stock SET quantity_left=%s WHERE stock_id=%s", (q1-3, ROW)); s1.commit()
c2.execute("UPDATE outlet_stock SET quantity_left=%s WHERE stock_id=%s", (q2-3, ROW)); s2.commit()
say(f"S1 and S2 both sold 3 (6 units sold) but only 5 existed. Stock shows {stock()} (S2 overwrote S1: 5-3) instead of rejecting a sale -> OVERSOLD / LOST UPDATE")
s1.close(); s2.close()

# ---- Part 2: atomic UPDATE with guard ---------------------------------------
say("\n=== PART 2: fix 1 - atomic UPDATE with a guard (SET q = q - 3 WHERE q >= 3) ===")
reset(); s1, s2 = conn(), conn(); c1, c2 = s1.cursor(), s2.cursor()
sql = "UPDATE outlet_stock SET quantity_left=quantity_left-3 WHERE stock_id=%s AND quantity_left>=3"
c1.execute(sql, (ROW,)); say("S1 update rows:", c1.rowcount)
def s2run(): c2.execute(sql, (ROW,)); return c2.rowcount
t, box = bg(s2run); time.sleep(1); say("S2 is waiting for S1's row lock..."); s1.commit(); t.join(); s2.commit()
say("S2 update rows:", box.get("r"), "-> second sale rejected cleanly. Stock now =", stock())
s1.close(); s2.close()

# ---- Part 3: SELECT FOR UPDATE ----------------------------------------------
say("\n=== PART 3: fix 2 - SELECT ... FOR UPDATE ===")
reset(); s1, s2 = conn(), conn(); c1, c2 = s1.cursor(), s2.cursor()
c1.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s FOR UPDATE", (ROW,)); say("S1 locked row, sees", c1.fetchone()[0])
def s2sel(): c2.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s FOR UPDATE", (ROW,)); return c2.fetchone()[0]
t, box = bg(s2sel); time.sleep(1); say("S2 is blocked waiting for the lock...")
c1.execute("UPDATE outlet_stock SET quantity_left=quantity_left-3 WHERE stock_id=%s", (ROW,)); s1.commit(); t.join()
say("S2 unblocked and now sees", box.get("r"), "-> app refuses the sale (needs 3). Stock now =", stock()); s2.rollback()
s1.close(); s2.close()

# ---- Part 4: SERIALIZABLE ---------------------------------------------------
say("\n=== PART 4: fix 3 - SERIALIZABLE isolation (one session gets error 40001 and retries) ===")
reset(); S = ext.ISOLATION_LEVEL_SERIALIZABLE
s1, s2 = conn(S), conn(S); c1, c2 = s1.cursor(), s2.cursor()
for c in (c1, c2): c.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s", (ROW,)); c.fetchone()
say("S1 and S2 both read 5 inside SERIALIZABLE transactions")
c1.execute("UPDATE outlet_stock SET quantity_left=quantity_left-3 WHERE stock_id=%s", (ROW,))
def s2upd(): c2.execute("UPDATE outlet_stock SET quantity_left=quantity_left-3 WHERE stock_id=%s", (ROW,))
t, box = bg(s2upd); time.sleep(1); s1.commit(); t.join()
e = box.get("e"); say("S2 result:", type(e).__name__ if e else "no error", "-", str(e).strip().splitlines()[0] if e else "")
s2.rollback(); say("S2 rolled back and would retry; stock now =", stock())
s1.close(); s2.close()

# ---- Part 5: READ COMMITTED vs REPEATABLE READ ------------------------------
say("\n=== PART 5: READ COMMITTED vs REPEATABLE READ ===")
reset(); rc, rr, w = conn(), conn(ext.ISOLATION_LEVEL_REPEATABLE_READ), conn()
crc, crr, cw = rc.cursor(), rr.cursor(), w.cursor()
for c in (crc, crr): c.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s", (ROW,)); c.fetchone()
cw.execute("UPDATE outlet_stock SET quantity_left=1 WHERE stock_id=%s", (ROW,)); w.commit()
crc.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s", (ROW,)); crr.execute("SELECT quantity_left FROM outlet_stock WHERE stock_id=%s", (ROW,))
say("Another session changed stock 5 -> 1 and committed.")
say("READ COMMITTED session now reads:", crc.fetchone()[0], "(sees the new value)")
say("REPEATABLE READ session now reads:", crr.fetchone()[0], "(still its snapshot)")
try: crr.execute("UPDATE outlet_stock SET quantity_left=quantity_left-3 WHERE stock_id=%s", (ROW,))
except Exception as e: say("REPEATABLE READ update of the changed row ->", type(e).__name__, "-", str(e).strip().splitlines()[0])
for c in (rc, rr, w): c.rollback(); c.close()

# ---- Part 6: deadlock and lock-order fix ------------------------------------
say("\n=== PART 6: deadlock (opposite lock order) and the fix (fixed lock order) ===")
a.execute("UPDATE outlet_stock SET quantity_left=50 WHERE stock_id IN (%s,%s)", (ROW, ROW2))
LOCK = "SELECT 1 FROM outlet_stock WHERE stock_id=%s FOR UPDATE"
s1, s2 = conn(), conn(); c1, c2 = s1.cursor(), s2.cursor()
c1.execute(LOCK, (ROW,)); c2.execute(LOCK, (ROW2,)); say("S1 locked row A; S2 locked row B")
t1, b1 = bg(lambda: c1.execute(LOCK, (ROW2,))); time.sleep(0.5)
t2, b2 = bg(lambda: c2.execute(LOCK, (ROW,)))
t1.join(); t2.join()
for n, b, s in (("S1", b1, s1), ("S2", b2, s2)):
    e = b.get("e"); say(n, "->", ("ERROR " + type(e).__name__ + ": " + str(e).strip().splitlines()[0]) if e else "got both locks")
    s.rollback()
s1.close(); s2.close()
say("Fix: both sessions lock the LOWER stock_id first, then the higher one.")
s1, s2 = conn(), conn(); c1, c2 = s1.cursor(), s2.cursor()
first, second = sorted((ROW, ROW2))
def ordered(c, s, n):
    def go():
        c.execute(LOCK, (first,)); time.sleep(0.5); c.execute(LOCK, (second,)); s.commit(); return n
    return go
t1, b1 = bg(ordered(c1, s1, "S1")); t2, b2 = bg(ordered(c2, s2, "S2")); t1.join(); t2.join()
say("S1:", "error " + str(b1["e"]) if "e" in b1 else "finished", "| S2:", "error " + str(b2["e"]) if "e" in b2 else "finished", "-> no deadlock")
s1.close(); s2.close()
reset(5); a.execute("UPDATE outlet_stock SET quantity_left=50 WHERE stock_id=%s", (ROW2,))
say("\nAll six demos finished.")

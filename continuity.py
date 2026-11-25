"""Opt-in rolling context, separate from confirmed personal memories."""
from dataclasses import dataclass

@dataclass
class Snapshot:
    revision: int
    through_id: int
    summary: str
    recent: list
    older: list

def snapshot(db, floor=0):
    revision, through_id, summary = db.execute(
        "SELECT revision,through_id,summary FROM conversation_state WHERE id=1").fetchone()
    if through_id < floor:
        through_id, summary = floor, ""
    recent = list(db.execute("SELECT id,question,answer FROM history WHERE id>? ORDER BY id DESC LIMIT 8", (floor,)))
    older = list(db.execute(
        "SELECT id,question,answer FROM history WHERE id>? AND id<? ORDER BY id LIMIT 8",
        (through_id, recent[-1][0]))) if recent else []
    return Snapshot(revision, through_id, summary, recent, older if len(older) >= 4 else [])

def reference(state):
    return {"prior_summary": state.summary,
            "older_turns_to_summarize": [{"question": q[:800], "answer": a[:500]}
                                          for _, q, a in state.older]}

def save(db, state, question, answer, summary):
    if not db.execute("UPDATE conversation_state SET revision=revision+1 WHERE id=1 AND revision=? RETURNING revision",
                      (state.revision,)).fetchone():
        return False
    if summary and state.older:
        db.execute("UPDATE conversation_state SET through_id=?,summary=? WHERE id=1",
                   (state.older[-1][0], summary))
    db.execute("INSERT INTO history(question,answer) VALUES (?,?)", (question, answer))
    db.execute("DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY id DESC LIMIT 30)")
    return True

def clear(db):
    db.execute("UPDATE conversation_state SET revision=revision+1,through_id=0,summary='' WHERE id=1")
    db.execute("DELETE FROM history")

def lock(db):
    db.execute("UPDATE conversation_state SET revision=revision WHERE id=1")

def export(db):
    lock(db)
    through_id, summary = db.execute("SELECT through_id,summary FROM conversation_state WHERE id=1").fetchone()
    rows = list(db.execute("SELECT id,question,answer FROM history ORDER BY id"))
    return {"history": [(q,a) for _,q,a in rows], "history_summary": summary,
            "summary_covered": sum(1 for i,_,_ in rows if i <= through_id) if summary else 0}

def restore(db, data):
    through_id = 0
    for index, row in enumerate(data.history):
        identifier = db.execute("INSERT INTO history(question,answer) VALUES (?,?) RETURNING id", row).fetchone()[0]
        if index < data.summary_covered:
            through_id = identifier
    db.execute("UPDATE conversation_state SET revision=revision+1,through_id=?,summary=? WHERE id=1",
               (through_id, data.history_summary))

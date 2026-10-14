"""Execute the compiled FMR status event with mock actor/transport natives.

Pass the text produced by `papyrus disassembly AIAgentNSFW.pex`.
"""
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8-sig")
body = re.search(r"\n\t\t\tname: 'OnFMRActorStatus'\n(.*?)(?=\n\t\t\tname:|\Z)", source, re.S)[1]
types = dict((name.lower(), typ.lower()) for typ, name in re.findall(r"^\s+(Actor|Bool|String|Int|None) (\S+)\s*$", body, re.M))
code = []
for op, raw in re.findall(r"opcode: '(\w+)', args: \[(.*?)\]\s*$", body, re.M):
    args = []
    for m in re.finditer(r"ident\(([^)]+)\)|integer\((-?\d+)\)|string\('(.*?)'\)|\b(none)\b", raw):
        args.append(("id", m[1].lower()) if m[1] is not None else ("val", int(m[2]) if m[2] is not None else m[3]))
    code.append((op, args))

def run(rank, actor="Test Mother"):
    env = {"akactor": actor, "factionrank": rank, "fathername": "Partner", "fatherraceid": 0}
    calls = []
    get = lambda a: env.get(a[1]) if a[0] == "id" else a[1]
    pc = 0
    for _ in range(200):
        if pc == len(code): return calls
        op, a = code[pc]
        step = 1
        if op == "ret":
            return calls
        if op == "assign": env[a[0][1]] = get(a[1])
        elif op == "cast":
            value = get(a[1]); typ = types.get(a[0][1])
            env[a[0][1]] = str(value) if typ == "string" else bool(value) if typ == "bool" else value
        elif op == "not": env[a[0][1]] = not get(a[1])
        elif op.startswith("cmp_"):
            x, y = get(a[1]), get(a[2])
            env[a[0][1]] = {"cmp_ge": lambda: x >= y, "cmp_le": lambda: x <= y, "cmp_eq": lambda: x == y}[op]()
        elif op == "isub": env[a[0][1]] = get(a[1]) - get(a[2])
        elif op == "strcat": env[a[0][1]] = str(get(a[1])) + str(get(a[2]))
        elif op == "jmp": step = get(a[0])
        elif op == "jmpf": step = 1 if get(a[0]) else get(a[1])
        elif op == "jmpt": step = get(a[1]) if get(a[0]) else 1
        elif op == "callmethod":
            assert a[0][1] == "getdisplayname"
            env[a[2][1]] = get(a[1])
        elif op == "callstatic":
            if a[0][1] == "aiagentfunctions":
                assert a[1][1] == "logmessageforactor"
                calls.append(tuple(get(x) for x in a[4:]))
            else: assert a[0][1] == "debug"
        else: raise AssertionError(op)
        pc += step
    raise AssertionError("event did not terminate")

expected = {0: "cleared", 1: "pregnant@1@Partner", 100: "pregnant@100@Partner",
            101: "recovery@1", 115: "recovery@15", 116: "cycle@menses",
            117: "cycle@follicular", 118: "cycle@ovulation", 119: "cycle@pms"}
for rank, payload in expected.items():
    assert run(rank) == [("Test Mother@" + payload, "fertility_notification", "Test Mother")], (rank, run(rank))
for rank in [-1, 120]: assert run(rank) == []
assert run(117, None) == []
print("fertility_status_bytecode_test: 12 compiled-event scenarios passed")

"""Run the compiled helper's small instruction set against mocked OThread slots.

Usage: python ostim_participant_bytecode_test.py AIAgentNSFW.disassemble.pas
This tests compiled control flow, not Skyrim's native OThread implementation.
"""
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding='utf-8-sig')
def function(name):
    return re.search(r'\.function ' + name + r'\b.*?\.endFunction', source, re.S | re.I)[0]

def run(thread, slots):
    body = function('GetOStimThreadParticipantsSafe').split('.code', 1)[1].split('.endCode')[0]
    code = [line.split(';')[0].strip() for line in body.splitlines() if line.split(';')[0].strip()]
    labels = {line[:-1]: i for i, line in enumerate(code) if line.endswith(':')}
    variables = {'threadid': thread}
    calls = []
    def get(v):
        if v.lower() == 'none': return None
        if re.fullmatch(r'-?\d+', v): return int(v)
        return variables[v.lower()]
    def put(k, v): variables[k.lower()] = v
    pc = 0
    for _ in range(300):
        line = code[pc]; pc += 1
        if line.endswith(':'): continue
        op, *a = line.split()
        if op == 'ArrayCreate': put(a[0], [None] * get(a[1]))
        elif op == 'Assign': put(a[0], get(a[1]))
        elif op == 'ArrayLength': put(a[0], len(get(a[1])))
        elif op == 'CompareLT': put(a[0], get(a[1]) < get(a[2]))
        elif op == 'CompareEQ': put(a[0], get(a[1]) == get(a[2]))
        elif op == 'Not': put(a[0], not get(a[1]))
        elif op == 'Cast': put(a[0], get(a[1]))
        elif op == 'JumpF':
            if not get(a[0]): pc = labels[a[1]]
        elif op == 'Jump': pc = labels[a[0]]
        elif op == 'IAdd': put(a[0], get(a[1]) + get(a[2]))
        elif op == 'CallStatic':
            assert a[:2] == ['OThread', 'GetActor'] or [x.lower() for x in a[:2]] == ['othread','getactor']
            calls.append((get(a[3]), get(a[4])))
            put(a[2], slots[get(a[4])])
        elif op == 'ArraySetElement': get(a[0])[get(a[1])] = get(a[2])
        elif op == 'Return': return get(a[0]), calls
        else: raise AssertionError('Unhandled compiled instruction: ' + line)
    raise AssertionError('helper did not terminate')

cases = [[None]*6, ['A','B',None,None,None,None], ['A',None,'B',None,'C',None], [None,'A',None,'B',None,None]]
for slots in cases:
    result, calls = run(12, slots)
    assert result == slots, f'original OStim slot indices lost: {slots} -> {result}'
    assert len(calls) == 6
result, calls = run(-1, [None]*6)
assert result == [None]*6 and calls == [], 'invalid thread must return an array without native calls'
checked = ['GetOStimThreadParticipantsSafe','FindActorIndexInList','CountValidActors','ResolveOStimOrgasmPartnerName','OstimOrgasm','OStimEnd','OStimThreadStart','OStimThreadEnd','OStimSubthreadStart','OStimSubthreadEnd']
for name in checked:
    body = function(name)
    array_locals = re.findall(r'\.local (\S+) actor\[\]', body, re.I)
    for local in array_locals:
        assert not re.search(r'\bCast\s+'+re.escape(local)+r'\s+None\b',body,re.I), f'{name} still casts None to an actor array'
teardown = function('OStimSubthreadEnd')
assert teardown.index('CountValidActors') < teardown.index('BuildScoringFromStash'), 'empty roster check must precede stashed teardown'
assert 'SendSceneEndWithHardSpeechFlush' in teardown and 'ClearStashedNpcSceneActors' in teardown
print('ostim_participant_bytecode_test: 5 roster cases, 10 function cast checks and teardown structure passed')

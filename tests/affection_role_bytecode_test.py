"""Exercise compiled role routing with mocked OStim sorting, not the Skyrim VM.

Usage: python affection_role_bytecode_test.py AIAgentNSFWSceneEngine.disassemble.pas
"""
import json
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding='utf-8-sig')

def function(name):
    match = re.search(r'\.function ' + name + r'\b.*?\.endFunction', source, re.S | re.I)
    assert match, name
    return match[0]

class Fixture:
    def __init__(self, player='Player', order=None):
        self.player = player
        self.order = order
        self.calls = []

    def run(self, name, *args):
        body = function(name)
        params = re.findall(r'\.param (\S+) \S+', body)
        values = dict(zip((p.lower() for p in params), args))
        types = dict((n.lower(), t.lower()) for n, t in re.findall(r'\.local (\S+) (\S+)', body))
        code = body.split('.code', 1)[1].split('.endCode')[0]
        lines = [line.strip() for line in code.splitlines() if line.strip()]
        labels = {line[:-1]: i for i, line in enumerate(lines) if line.endswith(':')}

        def get(token):
            if token.startswith('"'): return json.loads(token)
            if token.lower() == 'none': return None
            if token.lower() in ('true', 'false'): return token.lower() == 'true'
            if re.fullmatch(r'-?\d+', token): return int(token)
            return values[token.lower()]

        def put(token, value): values[token.lower()] = value

        pc = 0
        for _ in range(2000):
            line = lines[pc]; pc += 1
            if line.endswith(':'): continue
            tokens = re.findall(r'"(?:\\.|[^"\\])*"|[^\s]+', line.split(';@line')[0])
            op, *a = tokens
            if op == 'Assign': put(a[0], get(a[1]))
            elif op == 'Cast':
                value = get(a[1])
                put(a[0], str(value) if types.get(a[0].lower()) == 'string' else value)
            elif op == 'ArrayLength': put(a[0], len(get(a[1])))
            elif op == 'ArrayGetElement': put(a[0], get(a[1])[get(a[2])])
            elif op == 'ArrayFindElement':
                array, wanted, start = get(a[0]), get(a[2]), get(a[3])
                put(a[1], next((i for i in range(start, len(array)) if array[i] == wanted), -1))
            elif op == 'CompareEQ': put(a[0], get(a[1]) == get(a[2]))
            elif op == 'CompareLT': put(a[0], get(a[1]) < get(a[2]))
            elif op == 'CompareGTE': put(a[0], get(a[1]) >= get(a[2]))
            elif op == 'Not': put(a[0], not get(a[1]))
            elif op == 'IAdd': put(a[0], get(a[1]) + get(a[2]))
            elif op == 'StrCat': put(a[0], str(get(a[1])) + str(get(a[2])))
            elif op in ('JumpT', 'JumpF'):
                if bool(get(a[0])) == (op == 'JumpT'): pc = labels[a[1]]
            elif op == 'Jump': pc = labels[a[0]]
            elif op == 'Return': return get(a[0])
            elif op == 'CallStatic':
                cls, method, dest = a[:3]
                args = [get(x) for x in a[3:]]
                if cls.lower() == 'aiagentnsfwsceneengine':
                    result = ','.join(args[0]) if method.lower() == 'rosternames' else self.run(method, *args)
                elif cls.lower() == 'stringutil': result = args[0].find(args[1], args[2])
                elif cls.lower() == 'game': result = self.player
                elif cls.lower() == 'papyrusutil': result = [None] * args[0]
                elif cls.lower() == 'debug': result = None
                elif cls.lower() == 'oactorutil':
                    self.calls.append((method.lower(), args))
                    # The framework owns role selection. Return its fixture result unchanged.
                    result = list(self.order if self.order is not None else args[0])
                else: raise AssertionError(line)
                put(dest, result)
            else: raise AssertionError('Unhandled compiled instruction: ' + line)
        raise AssertionError('Compiled helper did not terminate')

checks = 0
acts = ['kiss', 'hug', 'holdhands', 'frenchkissing', 'kissing', 'cuddling', 'hugging', 'holdinghands']
for act in acts:
    for fresh in (True, False):
        fixture = Fixture(order=['Player', 'FemaleNPC'])
        result = fixture.run('ResolveOStimActorOrder', ['FemaleNPC', 'Player'], act, fresh)
        assert result == ['Player', 'FemaleNPC'], f'{act}: initiator incorrectly kept in slot 0: {result}'
        assert [c[0] for c in fixture.calls] == ['selectindexandsort' if fresh else 'sort']
        assert fixture.calls[0][1][1] == [], 'do not manufacture dominant overrides'
        if not fresh: assert fixture.calls[0][1][2] == -1, 'no forced player slot during transitions'
        checks += 1
    for player, roster, order in [
        ('Player', ['FemaleNPC','Player'], ['FemaleNPC','Player']),  # explicit role override
        ('FemalePlayer', ['FemaleNPC','FemalePlayer'], ['FemalePlayer','FemaleNPC']),
        ('Player', ['FemaleNPC','MaleNPC'], ['MaleNPC','FemaleNPC']),
        ('Player', ['FemaleNPC','Player','OtherNPC'], ['Player','OtherNPC','FemaleNPC']),
    ]:
        fixture = Fixture(player, order)
        assert fixture.run('ResolveOStimActorOrder', roster, act, True) == order
        assert fixture.calls[0][0] == ('selectindexandsort' if player in roster else 'sort')
        checks += 1
    assert Fixture().run('OStimActAvoidsSexualFallback', act), act
    checks += 1

for act in ['massage','bloodfeed']:
    fixture = Fixture(order=['Player','FemaleNPC'])
    assert fixture.run('ResolveOStimActorOrder', ['FemaleNPC','Player'], act, True) == ['FemaleNPC','Player']
    assert fixture.calls == [] and fixture.run('OStimActAvoidsSexualFallback', act)
    checks += 1
for invalid in [[], ['Player'], ['Player','Player'], [None,'Player'], ['Player','Stranger']]:
    assert Fixture(order=invalid).run('ResolveOStimActorOrder', ['FemaleNPC','Player'], 'kiss', False) == []
    checks += 1
for roster in [[], ['FemaleNPC']]:
    fixture = Fixture()
    assert fixture.run('ResolveOStimActorOrder', roster, 'kiss', True) == roster and fixture.calls == []
    checks += 1
fixture = Fixture(order=['Player','FemaleNPC'])
assert fixture.run('ResolveOStimActorOrder', ['FemaleNPC','Player'], 'sex', True) == ['Player','FemaleNPC']
assert not fixture.run('OStimActAvoidsSexualFallback', 'sex')
checks += 1

# Both entry points resolve roles before selecting animations. Transitions cannot show a role dialog.
start = function('StartOStimScene')
transition = function('TransitionOStimSceneToAct')
assert start.index('ResolveOStimActorOrder') < start.index('OStimExactSceneForAct')
assert re.search(r'CallStatic\s+\S+\s+ResolveOStimActorOrder\s+\S+\s+actors\s+sceneAct\s+false', transition, re.I)
assert transition.index('ResolveOStimActorOrder') < transition.index('OStimExactSceneForAct')
assert transition.index('OStimActorOrderMatches') < transition.index('StopOStimThreadAndWait')
assert 'RestartOStimScene' in transition or 'StartOStimScene' in transition
print(f'affection_role_bytecode_test: {checks} scenarios and start/transition routing checks passed')

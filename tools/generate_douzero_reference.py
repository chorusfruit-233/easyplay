#!/usr/bin/env python3
"""Replay app cases in the pinned upstream GameEnv, save encoder/model oracles.

Requires export requirements plus a checkout of kwai/DouZero at SOURCE_COMMIT.
Usage: python tools/generate_douzero_reference.py --source /path/to/DouZero
Inputs: build/douzero/cases.json (generate_douzero_cases.dart).
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    assert commit == '718a5c920bf3361e34178a38f3b80458e176b351'
    sys.path.insert(0, str(source))
    import numpy as np
    import torch
    from douzero.env.env import get_obs
    from douzero.env.game import GameEnv
    spec = importlib.util.spec_from_file_location('upstream_douzero_models', source / 'douzero/dmc/models.py')
    upstream = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upstream)
    model_dict = upstream.model_dict

    torch.set_num_threads(1)
    models = {}
    for role, model_type in model_dict.items():
        model = model_type().eval()
        model.load_state_dict(torch.load(ROOT / f'build/douzero/checkpoints/{role}.ckpt', weights_only=True, map_location='cpu'), strict=True)
        models[role] = model

    class Agent:
        action = None
        def act(self, _):
            return self.action

    def ranks(ids):
        return sorted(3 + c // 4 if c < 48 else 17 if c < 52 else 20 if c == 52 else 30 for c in ids)

    result = []
    for case in json.loads((ROOT / 'build/douzero/cases.json').read_text()):
        view = case['view']
        state = view['public']
        landlord = state['landlord']
        roles = {landlord: 'landlord', (landlord + 1) % 3: 'landlord_down', (landlord + 2) % 3: 'landlord_up'}
        agents = {role: Agent() for role in models}
        env = GameEnv(agents)
        env.card_play_init({
            **{roles[i]: ranks(hand) for i, hand in enumerate(case['initialHands'])},
            'three_landlord_cards': ranks(state['bottom']),
        })
        for play in state['history']:
            role = roles[play['seat']]
            assert role == env.acting_player_position
            agents[role].action = ranks(play['cards'])
            env.step()
        role = roles[view['seat']]
        assert role == env.acting_player_position
        infoset = env.game_infoset
        assert infoset.player_hand_cards == ranks(view['hand'])
        assert all(infoset.num_cards_left_dict[roles[i]] == n for i, n in enumerate(state['counts']))
        actions = [ranks(action) for action in case['actions']]
        assert all(action in infoset.legal_actions for action in actions)
        # The app deliberately excludes some upstream attachment variants.
        infoset.legal_actions = actions
        obs = get_obs(infoset)
        with torch.inference_mode():
            values = models[role](torch.from_numpy(obs['z_batch']), torch.from_numpy(obs['x_batch']), return_value=True)['values'].flatten().tolist()
        result.append({
            'name': case['name'], 'view': view, 'role': role, 'actions': case['actions'],
            'xPrefix': ''.join(str(int(v)) for v in obs['x_no_action']),
            'xSha256': hashlib.sha256(obs['x_batch'].tobytes()).hexdigest(),
            'z': ''.join(str(int(v)) for v in obs['z'].flatten()),
            'values': values,
        })
    path = ROOT / 'test/doudizhu/fixtures/douzero_reference.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({'sourceCommit': commit, 'cases': result}, ensure_ascii=False, indent=2) + '\n')
    print(f'{len(result)} upstream replay/feature/score cases -> {path}')


if __name__ == '__main__':
    main()

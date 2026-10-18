#!/usr/bin/env python3
"""Reproduce the bundled DouZero-WP ONNX models from pinned Apache-2.0 sources.

Install tools/requirements-douzero.txt (Torch from its CPU wheel index).
This is an offline development/export tool, not an application dependency.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SOURCE_COMMIT = '718a5c920bf3361e34178a38f3b80458e176b351'
WEIGHT_COMMIT = 'ca8c841552e08d602ad326d2c7450b683bf41226'
WEIGHT_REPO = 'pineoncellar/DouZero_API'
CHECKPOINTS = {
    'landlord': '132e26479fcb69f457ddbf1ad32a7bdc3aa73cde80a28cc91f29a62c6075955a',
    'landlord_up': 'b849ea518e66f088d635d3a29956da880f7b5ca89fabc5f70fc356c106ca6a15',
    'landlord_down': '964720faf583f4905662c94aaf73b1a97352b76ae3686fcc949beabbacdd95d1',
}


def download(url, path, expected=None):
    if not path.exists() or (expected and digest(path) != expected):
        path.parent.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(url, timeout=120).read()
        if expected and hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f'Checksum mismatch: {path.name}')
        path.write_bytes(data)
    return path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    import numpy as np
    import onnx
    import onnxruntime as ort
    import torch
    from torch import nn

    if (torch.__version__, np.__version__, onnx.__version__, ort.__version__) != (
        '2.5.1+cpu', '1.26.4', '1.17.0', '1.22.0',
    ):
        raise RuntimeError('Use the pinned tools/requirements-douzero.txt versions')
    torch.set_num_threads(1)
    source = download(
        f'https://raw.githubusercontent.com/kwai/DouZero/{SOURCE_COMMIT}/douzero/dmc/models.py',
        ROOT / 'build/douzero/source/models.py',
        '3ad5483bf3d82b3a4174ee3a8893891dafcd635590e9cd7372fabe5988e8a190',
    )
    spec = importlib.util.spec_from_file_location('upstream_douzero_models', source)
    upstream = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upstream)

    class ScoringModel(nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, z, x):
            # Every candidate sees the same history. Encode it once, rather
            # than repeating the LSTM for every possible action.
            history = self.model.lstm(z)[0][:, -1, :]
            x = torch.cat((history.expand(x.shape[0], -1), x), dim=-1)
            for layer in (self.model.dense1, self.model.dense2,
                          self.model.dense3, self.model.dense4, self.model.dense5):
                x = torch.relu(layer(x))
            return self.model.dense6(x)

    target = ROOT / 'assets/douzero'
    target.mkdir(parents=True, exist_ok=True)
    manifest = {
        'engine': 'DouZero-WP', 'sourceCommit': SOURCE_COMMIT,
        'weightRepository': WEIGHT_REPO, 'weightCommit': WEIGHT_COMMIT,
        'onnxRuntimeVersion': '1.22.0', 'opset': 17, 'models': {},
    }
    options = ort.SessionOptions()
    options.intra_op_num_threads = options.inter_op_num_threads = 1
    for role, checksum in CHECKPOINTS.items():
        checkpoint = download(
            f'https://raw.githubusercontent.com/{WEIGHT_REPO}/{WEIGHT_COMMIT}/baselines/douzero_WP/{role}.ckpt',
            ROOT / f'build/douzero/checkpoints/{role}.ckpt', checksum,
        )
        model = upstream.model_dict[role]().eval()
        model.load_state_dict(torch.load(checkpoint, map_location='cpu', weights_only=True), strict=True)
        scoring = ScoringModel(model).eval()
        width = 373 if role == 'landlord' else 484
        z = torch.zeros(1, 5, 162)
        x = torch.zeros(3, width)
        path = target / f'{role}.onnx'
        torch.onnx.export(
            scoring, (z, x), path, input_names=['z', 'x'], output_names=['values'],
            dynamic_axes={'x': {0: 'actions'}, 'values': {0: 'actions'}},
            opset_version=17, do_constant_folding=True,
        )
        graph = onnx.load(path)
        graph.doc_string = ''
        for node in graph.graph.node:
            node.doc_string = ''
        onnx.checker.check_model(graph)
        onnx.save(graph, path)
        session = ort.InferenceSession(str(path), options, providers=['CPUExecutionProvider'])
        random = np.random.default_rng(20261018)
        max_error = 0.0
        for count in (1, 3, 17, 129):
            history = random.integers(0, 2, (1, 5, 162)).astype(np.float32)
            features = random.integers(0, 2, (count, width)).astype(np.float32)
            with torch.inference_mode():
                expected = model(
                    torch.from_numpy(np.repeat(history, count, axis=0)),
                    torch.from_numpy(features), return_value=True,
                )['values'].numpy()
            actual = session.run(None, {'z': history, 'x': features})[0]
            np.testing.assert_allclose(actual, expected, rtol=2e-5, atol=2e-5)
            assert actual.argmax() == expected.argmax()
            max_error = max(max_error, float(np.max(np.abs(expected - actual))))
        manifest['models'][role] = {
            'file': path.name, 'sha256': digest(path), 'bytes': path.stat().st_size,
            'checkpointSha256': checksum, 'features': width,
        }
        print(f'{role}: {path.stat().st_size} bytes, max PyTorch/ONNX error {max_error:.9g}', flush=True)
    (target / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()

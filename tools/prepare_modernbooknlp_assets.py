"""CLI entrypoint for the same acquisition code used by the bundled worker."""
import argparse
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'assets'))
from modernbooknlp_assets import prepare

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    prepare(args.root, args.offline)

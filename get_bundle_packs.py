import json
import math
import sys
import os

def main():
    try:
        with open('BundlePackingInfo-Android.json', 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        full_packs = data.get('FullPatchPacks', [])
        update_packs = data.get('UpdatePacks', [])
        all_packs = [pack['PackName'] for pack in full_packs + update_packs if pack.get('PackName')]
        
        group_size = math.ceil(len(all_packs) / 4)
        groups = [all_packs[i:i+group_size] for i in range(0, len(all_packs), group_size)]
        groups_str = '|'.join([','.join(group) for group in groups])
        
        print(f'bundle-packs={groups_str}')
        print(f'Found {len(all_packs)} bundle packs, split into {len(groups)} groups', file=sys.stderr)
        
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        default_packs = 'FullPatch_100.zip,FullPatch_101.zip|FullPatch_102.zip,FullPatch_103.zip'
        default_packs_env = os.environ.get('DEFAULT_BUNDLE_PACKS', default_packs)
        print(f'bundle-packs={default_packs_env}')

if __name__ == "__main__":
    main()

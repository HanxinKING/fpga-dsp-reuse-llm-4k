"""Recompute descriptive comparisons from the published source data."""
from pathlib import Path
import json


def calculate(root):
    versions = json.loads((root / 'data/version_comparison.json').read_text(encoding='utf-8'))
    external = json.loads((root / 'data/external_comparisons.json').read_text(encoding='utf-8'))
    v = {row['id']: row for row in versions['versions']}
    e = {row['id']: row for row in external['records']}
    ours = v['q7_dual_joint_int24']
    ref = e['hummingbird_zcu104']
    reduction = lambda actual, baseline: 100 * (1-actual/baseline)
    return {
        'q7_internal_speed_increase_pct': 100*(ours['tokens_per_second']/v['q7_dual_fixed_int24']['tokens_per_second']-1),
        'hummingbird_zcu104_resource_reduction_pct': {key: reduction(ours[key if key!='dsp' else 'total_dsp'], ref[key]) for key in ('dsp','lut','ff','uram')},
        'hummingbird_zcu104_bram_increase_pct': 100*(ours['bram36']/ref['bram36']-1),
        'hummingbird_zcu104_throughput_fraction_pct': 100*ours['tokens_per_second']/ref['tps'],
        'descriptive_dsp_per_tps': {'q7': ours['total_dsp']/ours['tokens_per_second'], 'hummingbird_zcu104': ref['dsp']/ref['tps'],
                                   'reduction_pct': reduction(ours['total_dsp']/ours['tokens_per_second'], ref['dsp']/ref['tps'])},
        'reported_dsp_reduction_pct': {key: reduction(ours['total_dsp'],e[key]['dsp']) for key in ('hummingbird_kv260','li_date2025','llamaf','flightllm','lightmamba','tereffic')},
        'jetson_numeric_output_difference_pct': {'ChatLLM': 100*(4.86/3.94-1), 'llamacpp': 100*(4.86/4.44-1)},
        'q9_state_uram_reduction_pct': reduction(12,24),
        'q9_top_uram_reduction_pct': reduction(15,27),
        'strict_cross_platform_matched_speedup': False,
    }


if __name__ == '__main__':
    print(json.dumps(calculate(Path(__file__).resolve().parent.parent), ensure_ascii=False, indent=2))

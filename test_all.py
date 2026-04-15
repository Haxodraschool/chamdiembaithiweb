"""Test all 7 images and print summary."""
import sys, os
sys.path.insert(0, 'grading/engine')
import hi as engine

images = [f'anh\\{i}.jpg' for i in range(1, 8)]
results = []

for img in images:
    print(f"\n{'='*60}")
    print(f"  {img}")
    print(f"{'='*60}")
    r = engine.process_sheet(img, debug=True)
    if r:
        p1 = r.get('part1', {})
        p1_filled = sum(1 for v in p1.values() if v not in ('', '-', 'X'))
        p2 = r.get('part2', {})
        p3 = r.get('part3', {})
        results.append({
            'img': img, 'ok': True,
            'method': r['detect_method'],
            'sbd': r['sbd'], 'made': r['made'],
            'p1_filled': p1_filled, 'p2_count': len(p2), 'p3_count': len(p3),
            'overlay': os.path.exists(os.path.splitext(img)[0] + '_overlay.jpg'),
        })
    else:
        results.append({'img': img, 'ok': False})

print("\n\n" + "="*80)
print("  SUMMARY")
print("="*80)
for r in results:
    if r['ok']:
        ov = 'YES' if r['overlay'] else 'NO'
        print(f"  OK   {r['img']:12s}  Method={r['method']:25s}  SBD={r['sbd']}  MD={r['made']}  P1={r['p1_filled']}/40  Overlay={ov}")
    else:
        print(f"  FAIL {r['img']}")
print("="*80)
print(f"  {sum(1 for r in results if r['ok'])}/{len(results)} passed")
